#Requires -Version 5.1
# Fake process object and real journal engine: no host priority changes.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
foreach($name in @('Core','BackgroundBudget')){. (Join-Path $root ('lib\'+$name+'.ps1'))}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-budget-'+[guid]::NewGuid().ToString('N'))
$script:BnqqDataRoot=$temp;$script:checks=0;$script:scopeAllowed=$true;$script:partial=$false;$script:scopeReads=0
function Check($ok,$text){if(-not $ok){throw $text};$script:checks++}
function MustThrow([scriptblock]$Code){$hit=$false;try{& $Code|Out-Null}catch{$hit=$true};Check $hit 'Expected priority refusal'}
$script:fake=[pscustomobject]@{Id=40;ProcessName='msedge';StartTime=[datetime]'2026-01-01T12:00:00Z';Handle=[IntPtr]123;PriorityClass='Normal';Disposals=0}
$script:fake|Add-Member ScriptMethod Dispose {$this.Disposals++}
function Get-Process {param($Id,$ErrorAction);if($Id -eq $script:fake.Id){return $script:fake}}
function Assert-BnqqCpuProcessScope {param($Process,$Handle);$script:scopeReads++;Check ($Handle -eq [IntPtr]123) 'Handle was not cached';if(-not $script:scopeAllowed){throw 'Foreign session/SID fixture'}}
try {
 $s=Get-BnqqBudgetState 40
 Check ($s.Priority -eq 'Normal' -and $script:scopeReads -eq 1 -and $script:fake.Disposals -eq 1) 'Snapshot/scope/disposal failed'
 $sample=$s|Select-Object *;$sample|Add-Member NoteProperty RateMsPerSecond 100
 $p=Get-BnqqBudgetPlan @($sample) @('msedge')
 Check ($p.Operations.Count -eq 1 -and $p.Operations[0].After.Priority -eq 'BelowNormal') 'Budget plan missing'
 Check ($script:fake.PriorityClass -eq 'Normal') 'Preview changed host fixture'
 MustThrow {Get-BnqqBudgetPlan @($sample) @('Discord')}
 MustThrow {Get-BnqqBudgetPlan @($sample) @('OneDrive')}
 $script:scopeAllowed=$false;MustThrow {Get-BnqqBudgetState 40}
 MustThrow {Set-BnqqBudgetState $p.Operations[0].After $s}
 Check ($script:fake.PriorityClass -eq 'Normal') 'Foreign scope mutated'
 $script:scopeAllowed=$true
 $wrong=$s|Select-Object *;$wrong.StartTime='other-lifetime'
 Check ($null -eq (Get-BnqqBudgetState 40 $wrong)) 'Reused PID read accepted'
 MustThrow {Set-BnqqBudgetState $p.Operations[0].After $wrong}
 $wrong=$s|Select-Object *;$wrong.Priority='High'
 MustThrow {Set-BnqqBudgetState $p.Operations[0].After $wrong}
 $j=New-BnqqJournal 'priority-fixture'
 Invoke-BnqqJournalOperation $j $p.Operations[0]
 Check ($script:fake.PriorityClass -eq 'BelowNormal') 'Journal did not apply'
 $disk=Get-Content $j.File -Raw|ConvertFrom-Json
 Check ($disk.Entries[0].Before.Priority -eq 'Normal' -and $disk.Entries[0].Status -eq 'Applied') 'Original state not journaled'
 $script:fake.PriorityClass='AboveNormal';MustThrow {Restore-BnqqJournal $j.File}
 Check ($script:fake.PriorityClass -eq 'AboveNormal') 'External priority overwritten'
 $script:fake.PriorityClass='BelowNormal';Restore-BnqqJournal $j.File|Out-Null
 Check ($script:fake.PriorityClass -eq 'Normal') 'Priority not restored'
 Restore-BnqqJournal $j.File|Out-Null
 # Closed or recycled processes are never mutated during recovery.
 $p=Get-BnqqBudgetPlan @($sample) @('msedge');$j=New-BnqqJournal 'exited-fixture';Invoke-BnqqJournalOperation $j $p.Operations[0]
 $script:fake.StartTime=$script:fake.StartTime.AddSeconds(1);$script:fake.PriorityClass='High'
 $r=Restore-BnqqJournal $j.File
 Check ($r.Entries[0].Status -eq 'Exited' -and $script:fake.PriorityClass -eq 'High') 'Recycled PID changed during recovery'
 # Entire journal is validated before the first target write.
 $op=$p.Operations[0];$op.Before.Name='cs2';MustThrow {Assert-BnqqOperation $op}
 $op.Before.Name='msedge';$op.After.Priority='High';MustThrow {Assert-BnqqOperation $op}
 $script:fake.ProcessName='cs2';MustThrow {Get-BnqqBudgetState 40}
 $script:fake.ProcessName='msedge';$script:fake.PriorityClass='BelowNormal';$sample.StartTime=$script:fake.StartTime.ToUniversalTime().ToString('o')
 Check (@((Get-BnqqBudgetPlan @($sample) @('msedge')).Operations).Count -eq 0) 'Already-low process was promoted/demoted'
 $script:fake.PriorityClass='Idle'
 Check (@((Get-BnqqBudgetPlan @($sample) @('msedge')).Operations).Count -eq 0) 'Idle process was promoted'
 $script:planReads=0;$script:skipFirst=$false
 function Get-BnqqBudgetState {
  param($ProcessId,$Expected)
  $script:planReads++
  if($script:skipFirst -and $ProcessId -eq 1){return $null}
  if($script:skipFirst -and $ProcessId -eq 2){throw 'Denied fixture'}
  [pscustomobject]@{ProcessId=$ProcessId;Name='msedge';StartTime=$Expected.StartTime;Priority=$(if($script:skipFirst -and $ProcessId -eq 3){'BelowNormal'}else{'Normal'})}
 }
 $many=@(1..128|ForEach-Object {[pscustomobject]@{ProcessId=$_;Name='msedge';StartTime=('p'+$_)}})
 $p=Get-BnqqBudgetPlan $many @('msedge') -MaxOperations 2
 Check ($script:planReads -eq 2 -and $p.Operations.Count -eq 2 -and $p.Operations[1].Before.ProcessId -eq 2) 'Planner queried candidates beyond admission budget'
 $script:planReads=0;$script:skipFirst=$true
 $p=Get-BnqqBudgetPlan $many @('msedge') -MaxOperations 2
 Check ($script:planReads -eq 5 -and $p.Operations.Count -eq 2 -and $p.Errors.Count -eq 1 -and $p.Operations[0].Before.ProcessId -eq 4) 'No-op/exit/denial starved eligible candidates'
 $script:planReads=0;$many[127].Name='cs2'
 MustThrow {Get-BnqqBudgetPlan $many @('msedge') -MaxOperations 2}
 Check ($script:planReads -eq 0) 'Planner did not validate all sample targets before early exit'
 $many[127].Name='msedge';$script:skipFirst=$false
 $p=Get-BnqqBudgetPlan $many @('msedge')
 Check ($script:planReads -eq 128 -and $p.Operations.Count -eq 128) 'Default planning contract changed'
 MustThrow {Get-BnqqBudgetPlan $many @('msedge') -MaxOperations 0}
 ('PASS: background priority '+$script:checks+' checks; scope, identity, admission budget, conflicts, recovery and no-op')
}finally{
 if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
}
