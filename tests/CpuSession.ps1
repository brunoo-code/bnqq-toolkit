$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($name in @('Core','CpuSession')){. (Join-Path $script:BnqqRoot ('lib\'+$name+'.ps1'))}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-cpu-'+[guid]::NewGuid().ToString('N'))
$script:BnqqDataRoot=$temp;$script:qa=$true;$script:healthy=$true;$script:partial=$false;$script:failHealth=$false;$script:writes=0
$script:state=[pscustomobject]@{ProcessId=20;Name='msedge';StartTime='fixture-start';Sets=@()}
$script:power=[pscustomobject]@{Scheme='11111111-1111-1111-1111-111111111111';Sub='SUB_PROCESSOR';Setting='CPMINCORES';AC=10;DC=20}
$script:table=@(0..7|ForEach-Object {[pscustomobject]@{Id=(100+$_);Group=0;Logical=$_;Core=($_%4);Efficiency=0;Flags=0}})
function Check($ok,$message){if(-not $ok){throw $message}}
function MustThrow([scriptblock]$Code){$caught=$false;try{& $Code|Out-Null}catch{$caught=$true};Check $caught 'Expected refusal'}
function Get-BnqqCpuSetTable {return $script:table}
function Test-BnqqAdmin {return $true}
function Assert-BnqqHeavyQa {if(-not $script:qa){throw 'WHEA/QA fixture refusal'}}
function Get-BnqqPhaseHealth {param($Since);return [pscustomobject]@{Healthy=$script:healthy;WheaCount=$(if($script:healthy){0}else{1});KernelPower41=0;Error=$null}}
function Get-Process {param($Name,$ErrorAction);if($Name -eq 'msedge'){return [pscustomobject]@{Id=20;ProcessorAffinity=255}};if($Name -eq 'cs2'){return [pscustomobject]@{Id=10}}}
function Get-BnqqSessionProcess {param($ProcessId);return [pscustomobject]@{ProcessId=10;Name='cs2';StartTime='fixed-game';Priority='Normal'}}
function Get-BnqqCpuSetProcessState {param($ProcessId,$Expected);if($Expected -and $Expected.StartTime -cne $script:state.StartTime){return $null};return ($script:state|Select-Object *)}
function Set-BnqqCpuSetProcessState {
 param($State,$Expected)
 Check (Test-BnqqSameValue $Expected $script:state) 'Changed state not refused'
 $j=@(Get-ChildItem (Join-Path $temp 'journals') -Filter '*.json'|ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json}|Where-Object Status -ne 'Restored')
 Check ($j.Count -eq 1 -and @($j[0].Entries|Where-Object Kind -eq 'CpuSets').Count -eq 1) 'Missing durable CPU Sets backup'
 $script:state=$State|Select-Object *;$script:writes++
 if($script:partial){$script:partial=$false;throw 'Injected failure after CPU Sets write'}
}
function Get-BnqqPowerSnapshot {param($Scheme,$Setting);Check ($Setting -eq 'CPMINCORES') 'Wrong power setting read';return ($script:power|Select-Object *)}
function Set-BnqqOperationState {
 param($Op,$State)
 Assert-BnqqOperation $Op
 if($Op.Kind -eq 'CpuSets'){Set-BnqqCpuSetProcessState $State (Get-BnqqOperationState $Op)}
 elseif($Op.Kind -eq 'Power'){$script:power=$State|Select-Object *;$script:writes++}
 else{throw 'Unexpected mutation'}
}
function Wait-BnqqCpuSession {
 param($Game,$Since)
 Check (($script:state.Sets -join ',') -eq '103,107') 'Did not select actual SMT siblings'
 Check ($Game.StartTime -eq 'fixed-game') 'Missing game identity'
 if($script:failHealth){$script:healthy=$false;Assert-BnqqPhaseHealth $Since}
}
try {
 $ids=@(Get-BnqqCpuBackgroundIds $table 1)
 Check (($ids -join ',') -eq '103,107') 'Parity assumption instead of actual topology'
 MustThrow {Get-BnqqCpuBackgroundIds $table 3}
 $bad=@($table|ForEach-Object {$_|Select-Object *});$bad[0].Group=1;MustThrow {Get-BnqqCpuBackgroundIds $bad 1}
 $bad[0].Group=0;$bad[0].Efficiency=1;MustThrow {Get-BnqqCpuBackgroundIds $bad 1}
 $bad[0].Efficiency=0;$bad[0].Flags=2;MustThrow {Get-BnqqCpuBackgroundIds $bad 1}
 $bad[0].Flags=0;$bad[0].Id=$bad[1].Id;MustThrow {Get-BnqqCpuBackgroundIds $bad 1}
 MustThrow {Get-BnqqCpuSessionPlan @('cs2') 1}
 MustThrow {Get-BnqqCpuSessionPlan @('LAMZU Aurora') 1}
 $plan=Get-BnqqCpuSessionPlan @('msedge') 1 -UnparkCpu
 Check ($plan.Operations.Count -eq 2 -and $plan.Operations[0].After.AC -eq 100 -and $plan.Operations[0].After.DC -eq 20 -and $script:writes -eq 0) 'Plan/DC preservation/no-write failed'
 $script:qa=$false;MustThrow {Invoke-BnqqCpuSession -Action run -Apps msedge -BackgroundCores 1 -UnparkCpu}
 Check ($script:writes -eq 0) 'Baseline guard wrote state';$script:qa=$true
 $r=Invoke-BnqqCpuSession -Action run -Apps msedge -BackgroundCores 1 -UnparkCpu
 Check ($r.Status -eq 'Restored' -and $script:state.Sets.Count -eq 0 -and $script:power.AC -eq 10 -and $script:power.DC -eq 20) 'Full CPU/parking restore failed'
 $count=$script:writes;Restore-BnqqJournal $r.Journal|Out-Null;Check ($script:writes -eq $count) 'Restore not idempotent'
 $script:partial=$true;MustThrow {Invoke-BnqqCpuSession -Action run -Apps msedge -BackgroundCores 1}
 Check ($script:state.Sets.Count -eq 0) 'Interrupted CPU Sets write not recovered'
 $script:failHealth=$true;MustThrow {Invoke-BnqqCpuSession -Action run -Apps msedge -BackgroundCores 1 -UnparkCpu}
 Check ($script:state.Sets.Count -eq 0 -and $script:power.AC -eq 10) 'New WHEA did not revert current vector'
 $script:healthy=$true;$script:failHealth=$false
 $script:state.Sets=@(103);$plan=Get-BnqqCpuSessionPlan @('msedge') 1
 Check ($plan.Operations.Count -eq 0) 'Existing narrower assignment expanded'
 $script:state.Sets=@();$script:power.AC=100
 Check ((Invoke-BnqqCpuSession -Action run -BackgroundCores 1 -UnparkCpu).Status -eq 'NoChanges') 'Already unparked plan should be no-op'
 $before=$script:state|Select-Object *;$after=$before|Select-Object *;$after.Sets=@(103,107)
 $j=New-BnqqJournal 'conflict';$op=[pscustomobject]@{Kind='CpuSets';Before=$before;After=$after};Invoke-BnqqJournalOperation $j $op
 $script:state.Sets=@(102);$count=$script:writes
 MustThrow {Restore-BnqqJournal $j.File};Check ($script:writes -eq $count -and $script:state.Sets[0] -eq 102) 'External CPU Sets overwritten'
 $script:state.Sets=@(103,107);Restore-BnqqJournal $j.File|Out-Null
 $op.Before.Name='cs2';$op.After.Name='cs2';MustThrow {Assert-BnqqOperation $op}
 $op.Before.Name='msedge';$op.After.Name='msedge';$op.After.Sets=@(-1);MustThrow {Assert-BnqqOperation $op}
 $op.After.Sets=@(103,103);MustThrow {Assert-BnqqOperation $op}
 $p=$power|Select-Object *;$p.AC=101;$pAfter=$p|Select-Object *;$pAfter.AC=100
 MustThrow {Assert-BnqqOperation ([pscustomobject]@{Kind='Power';Before=$p;After=$pAfter})}
 Check (Test-Path (Join-Path $temp 'bnqq-night-log.txt')) 'Missing night error log'
 'PASS: CPU topology, real SMT siblings, bounds, no-op, baseline guard, AC-only parking, native write-ahead adapter, partial failure, WHEA rollback, conflicts and allowlists'
}finally{
 $resolved=[IO.Path]::GetFullPath($temp)
 if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test cleanup'}
 if([IO.Directory]::Exists($resolved)){[IO.Directory]::Delete($resolved,$true)}
}
