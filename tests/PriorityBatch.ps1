#Requires -Version 5.1
# Real atomic journal files, mock process states. No host priorities or OS changes.
$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $script:BnqqRoot 'lib\Core.ps1')
. (Join-Path $script:BnqqRoot 'lib\BackgroundBudget.ps1')
$tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temp=[IO.Path]::GetFullPath((Join-Path $tempBase ('bnqq-priority-batch-'+[guid]::NewGuid().ToString('N'))))
if(-not $temp.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture path outside temp'}
$script:BnqqDataRoot=$temp;$script:checks=0
$script:atomicWriter=${function:Write-BnqqAtomicJson}
function Check($ok,$message){if(-not $ok){throw $message};$script:checks++}
function MustThrow([scriptblock]$code){$hit=$false;try{& $code|Out-Null}catch{$hit=$true};Check $hit 'Expected rejection'}
function Reset-Fixture {
 $script:currentJournal=$null;$script:persistCalls=0;$script:targetWrites=0;$script:mode='normal';$script:verifyPrepared=$true;$script:expectedPreparedCount=2
 $script:states=@{}
 foreach($n in 1..2){$script:states[$n]=[pscustomobject]@{ProcessId=$n;Name='msedge';StartTime=('p'+$n);Priority='Normal'}}
 $script:currentJournal=New-BnqqJournal 'priority-batch-fixture'
 $script:persistCalls=0
}
function New-FixtureOps {
 foreach($n in 1..2){$b=$script:states[$n]|Select-Object *;$a=$b|Select-Object *;$a.Priority='BelowNormal';[pscustomobject]@{Kind='BackgroundPriority';Before=$b;After=$a}}
}
function Write-BnqqAtomicJson {
 param($Value,[string]$Path)
 if($script:currentJournal -and $Path -ceq $script:currentJournal.File){
  $script:persistCalls++
  if($script:mode -eq 'reject-prepare' -and $script:persistCalls -eq 1){throw 'Fixture prepare IO failure'}
  if($script:mode -eq 'crash-after-first' -and $script:persistCalls -gt 1){throw 'Fixture disk unavailable after Prepared'}
  if($script:mode -eq 'reject-commit' -and $script:persistCalls -eq 2){throw 'Fixture commit IO failure'}
 }
 & $script:atomicWriter $Value $Path
 if($script:mode -eq 'race' -and $script:persistCalls -eq 1){$script:states[2].Priority='High'}
 if($script:mode -eq 'single-race' -and $script:persistCalls -eq 1){$script:states[1].Priority='High'}
}
function Get-BnqqBudgetState {
 param([int]$ProcessId,$Expected)
 $s=$script:states[$ProcessId]
 if(-not $s -or ($Expected -and ($s.StartTime -cne $Expected.StartTime -or $s.Name -ine $Expected.Name))){return $null}
 return ($s|Select-Object *)
}
function Set-BnqqBudgetState {
 param($State,$Expected)
 $s=Get-BnqqBudgetState $State.ProcessId $State
 if(-not (Test-BnqqSameValue $s $Expected)){throw 'Fixture external state conflict'}
 if($script:verifyPrepared -and $State.Priority -eq 'BelowNormal'){
  $disk=Get-Content -LiteralPath $script:currentJournal.File -Raw|ConvertFrom-Json
  Check (@($disk.Entries).Count -eq $script:expectedPreparedCount -and @($disk.Entries|Where-Object Status -cne 'Prepared').Count -eq 0) 'All originals not durable before mutation'
 }
 $script:states[[int]$State.ProcessId]=$State|Select-Object *;$script:targetWrites++
 if($script:mode -eq 'partial-second' -and $State.ProcessId -eq 2){throw 'Fixture partial second write'}
 if($script:mode -eq 'crash-after-first'){throw 'Fixture interrupted after first target write'}
}
try{
 Reset-Fixture;$script:verifyPrepared=$false
 foreach($op in @(New-FixtureOps)){Invoke-BnqqJournalOperation $script:currentJournal $op}
 Check ($script:persistCalls -eq 4 -and $script:targetWrites -eq 2) 'Single-operation persistence reference changed'
 Reset-Fixture;$ops=@(New-FixtureOps)
 Invoke-BnqqPriorityBatch $script:currentJournal $ops
 Check ($script:persistCalls -eq 2 -and $script:targetWrites -eq 2) 'Batch did not use exactly two durable writes'
 $disk=Get-Content $script:currentJournal.File -Raw|ConvertFrom-Json
 Check (@($disk.Entries|Where-Object Status -cne 'Applied').Count -eq 0) 'Successful batch not committed'
 $script:verifyPrepared=$false;Restore-BnqqJournal $script:currentJournal.File|Out-Null
 Check ($script:states[1].Priority -ceq 'Normal' -and $script:states[2].Priority -ceq 'Normal') 'Batch originals not restored'
 $before=$script:targetWrites;Restore-BnqqJournal $script:currentJournal.File|Out-Null
 Check ($before -eq $script:targetWrites) 'Recovery not idempotent'
 Reset-Fixture;$script:expectedPreparedCount=1;$ops=@(New-FixtureOps)
 Invoke-BnqqPriorityBatch $script:currentJournal @($ops[0])
 Check ($script:persistCalls -eq 2 -and $script:targetWrites -eq 1 -and $script:states[2].Priority -ceq 'Normal') 'Single-candidate batch contract changed'
 foreach($fixtureMode in @('reject-prepare','partial-second','reject-commit','crash-after-first')){
  Reset-Fixture;$script:mode=$fixtureMode
  MustThrow {Invoke-BnqqPriorityBatch $script:currentJournal @(New-FixtureOps)}
  if($fixtureMode -eq 'reject-prepare'){Check ($script:targetWrites -eq 0) 'Failed write-ahead changed targets'}
  if($fixtureMode -eq 'crash-after-first'){
   $disk=Get-Content $script:currentJournal.File -Raw|ConvertFrom-Json
   Check ($disk.Status -ceq 'Open' -and @($disk.Entries|Where-Object Status -cne 'Prepared').Count -eq 0) 'Crash simulation did not retain original Prepared file'
  }
  $script:mode='normal';$script:verifyPrepared=$false
  Restore-BnqqJournal $script:currentJournal.File|Out-Null
  Check ($script:states[1].Priority -ceq 'Normal' -and $script:states[2].Priority -ceq 'Normal') ('Recovery failed: '+$fixtureMode)
 }
 Reset-Fixture;$script:mode='race'
 MustThrow {Invoke-BnqqPriorityBatch $script:currentJournal @(New-FixtureOps)}
 Check ($script:states[2].Priority -ceq 'High' -and $script:targetWrites -eq 1) 'Batch overwrote concurrent external priority'
 $script:mode='normal';$script:verifyPrepared=$false
 MustThrow {Restore-BnqqJournal $script:currentJournal.File}
 Check ($script:states[1].Priority -ceq 'Normal' -and $script:states[2].Priority -ceq 'High') 'Recovery overwrote external conflict or missed first target'
 Reset-Fixture;$script:mode='single-race';$script:verifyPrepared=$false
 MustThrow {Invoke-BnqqJournalOperation $script:currentJournal @(New-FixtureOps)[0]}
 Check ($script:targetWrites -eq 0 -and $script:states[1].Priority -ceq 'High') 'Single-operation adapter replaced expected original with newer state'
 Reset-Fixture;$ops=@(New-FixtureOps);$ops[1].After.Priority='High'
 MustThrow {Invoke-BnqqPriorityBatch $script:currentJournal $ops}
 Check ($script:targetWrites -eq 0 -and $script:persistCalls -eq 0) 'Invalid second operation reached WAL/target'
 Reset-Fixture;$ops=@(New-FixtureOps)
 MustThrow {Invoke-BnqqPriorityBatch $script:currentJournal @($ops[0],$ops[0])}
 MustThrow {Invoke-BnqqPriorityBatch $script:currentJournal @($ops[0],$ops[1],$ops[0])}
 Check ($script:targetWrites -eq 0 -and $script:persistCalls -eq 0) 'Invalid batch size/duplicates wrote state'
 $script:currentJournal.Data.Owner='foreign'
 MustThrow {Invoke-BnqqPriorityBatch $script:currentJournal $ops}
 Check ($script:targetWrites -eq 0) 'Foreign-owner journal wrote targets'
 Reset-Fixture;$ops=@(New-FixtureOps);$script:states[2].Priority='High'
 MustThrow {Invoke-BnqqPriorityBatch $script:currentJournal $ops}
 Check ($script:targetWrites -eq 0 -and $script:persistCalls -eq 0) 'Preflight conflict changed first target'
 Reset-Fixture;$ops=@(New-FixtureOps)
 MustThrow {Invoke-BnqqPriorityBatch $script:currentJournal @()}
 $script:currentJournal.Data.Entries=@(1..512)
 MustThrow {Invoke-BnqqPriorityBatch $script:currentJournal $ops}
 Check ($script:targetWrites -eq 0 -and $script:persistCalls -eq 0) 'Empty/oversized epoch wrote state'
 Reset-Fixture;$script:currentJournal.Data.Entries=@([pscustomobject]@{Status='Prepared'})
 MustThrow {Invoke-BnqqPriorityBatch $script:currentJournal @(New-FixtureOps)}
 Check ($script:targetWrites -eq 0 -and $script:persistCalls -eq 0) 'Pending batch accepted new participants'
 "PASS: priority batch $script:checks checks; durable prepare/commit, crash recovery, external races and admission limits"
}finally{
 if([IO.Path]::GetFullPath($temp) -ne $temp -or -not $temp.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase)){throw 'Cleanup path changed'}
 if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
}
