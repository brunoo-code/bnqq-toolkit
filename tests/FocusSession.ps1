#Requires -Version 5.1
# Full controller lifecycle with fake clock/processes/CPU Sets/SCM. No host tuning.
$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($n in @('Core','Governance','CpuSession','BackgroundBudget','Maintenance','FocusSession')){. (Join-Path $script:BnqqRoot ('lib\'+$n+'.ps1'))}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-focus-'+[guid]::NewGuid().ToString('N'))
$script:BnqqDataRoot=$temp;$script:checks=0
function Check($ok,$text){if(-not $ok){throw $text};$script:checks++}
function MustThrow([scriptblock]$Code){$hit=$false;try{& $Code|Out-Null}catch{$hit=$true};Check $hit 'Expected refusal'}
function Reset {
 if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
 $script:tick=0;$script:qa=$true;$script:failHealth=$false;$script:failCpu=$false;$script:stop=$false;$script:service=4;$script:serviceWrites=0;$script:cpuWrites=0;$script:frameGuardChecked=$false;$script:planReads=0
 $script:clock=[pscustomobject]@{Elapsed=[pscustomobject]@{TotalMinutes=0;TotalSeconds=0}}
 $script:processes=@{};foreach($n in 40..43){$script:processes[$n]=[pscustomobject]@{ProcessId=$n;Name='msedge';StartTime=('p'+$n);Sets=@()}}
 $script:priorities=@{};foreach($n in 40..43){$script:priorities[$n]='Normal'};$script:priorityWrites=0;$script:failPriority=$false
 $script:endTick=22;$script:quietAfter=100000
}
function Assert-BnqqHeavyQa {if(-not $script:qa){throw 'WHEA fixture refusal'}}
function Assert-BnqqPhaseHealth {param($Since);if($script:failHealth -and $script:tick -ge 10){throw 'New WHEA fixture'}}
function Test-BnqqAdmin {return $true}
function New-BnqqFocusClock {return $script:clock}
function Get-Process {param($Name,$ErrorAction);[pscustomobject]@{Id=10}}
function Get-BnqqFocusIdentity {
 param($ProcessId)
 if($ProcessId -eq 10 -and $script:tick -ge $script:endTick){return $null}
 [pscustomobject]@{ProcessId=$ProcessId;Name=$(if($ProcessId -eq 10){'cs2'}else{'powershell'});StartTime='fixed'}
}
function Get-BnqqForegroundPid {if($script:tick -in @(7,8)){return 0};return 10}
function Get-BnqqFocusSamples {
 param($Apps)
 foreach($n in 40..43){if($n -eq 43 -and $script:tick -lt 9){continue};$s=$script:processes[$n];[pscustomobject]@{ProcessId=$n;Name='msedge';StartTime=$s.StartTime;CpuMs=([math]::Min($script:tick,$script:quietAfter)*(100+($n-40)*10))}}
}
function Get-BnqqCpuSessionPlan {
 param($Apps,$BackgroundCores)
 $script:planReads++
 $ops=@(foreach($n in 40..43){if($n -eq 43 -and $script:tick -lt 9){continue};$b=$script:processes[$n]|Select-Object *;if($b.Sets.Count){continue};$a=$b|Select-Object *;$a.Sets=@(103);[pscustomobject]@{Kind='CpuSets';Before=$b;After=$a}})
 [pscustomobject]@{CpuSetIds=@(103);Operations=$ops;Errors=@()}
}
function Get-BnqqCpuSetProcessState {
 param($ProcessId,$Expected)
 $s=$script:processes[[int]$ProcessId]
 if(-not $s -or $s.StartTime -cne $Expected.StartTime){return $null}
 return ($s|Select-Object *)
}
function Get-BnqqBudgetState {
 param($ProcessId,$Expected)
 $p=$script:processes[[int]$ProcessId]
 if(-not $p -or ($Expected -and $p.StartTime -cne $Expected.StartTime)){return $null}
 [pscustomobject]@{ProcessId=$p.ProcessId;Name=$p.Name;StartTime=$p.StartTime;Priority=$script:priorities[[int]$ProcessId]}
}
function Set-BnqqBudgetState {
 param($State,$Expected)
 Check ($State.ProcessId -ne 10 -and (Test-BnqqSameValue (Get-BnqqBudgetState $State.ProcessId) $Expected)) 'Priority identity lost/game changed'
 $script:priorities[[int]$State.ProcessId]=$State.Priority;$script:priorityWrites++
 if($script:failPriority -and $State.Priority -eq 'BelowNormal'){$script:failPriority=$false;throw 'Partial priority write fixture'}
}
function Set-BnqqCpuSetProcessState {
 param($State,$Expected)
 Check ($State.ProcessId -ne 10) 'Game scheduling changed'
 Check (Test-BnqqSameValue $Expected $script:processes[[int]$State.ProcessId]) 'PID identity lost'
 $script:processes[[int]$State.ProcessId]=$State|Select-Object *;$script:cpuWrites++
 if($script:failCpu -and $State.Sets.Count){$script:failCpu=$false;throw 'Partial CPU write fixture'}
}
function Get-BnqqMaintenancePlan {
 param($PauseSearch,$DeferMaintenance)
 $b=[pscustomobject]@{Name='WSearch';State=4;ConfigurationHash=('A'*64)};$a=$b|Select-Object *;$a.State=1
 [pscustomobject]@{Operations=@([pscustomobject]@{Kind='Service';Before=$b;After=$a});RequiresAdmin=$true;Notes=@()}
}
function Get-BnqqSearchState {[pscustomobject]@{Name='WSearch';State=$script:service;ConfigurationHash=('A'*64)}}
function Invoke-BnqqSearchControl {param($Running);$script:service=if($Running){4}else{1};$script:serviceWrites++}
function Start-Sleep {
 param($Seconds)
 if($script:tick -eq 0){MustThrow {Assert-BnqqNoDynamicFocus};$script:frameGuardChecked=$true}
 if($script:tick -eq 7){Check (-not @($script:processes.Values|Where-Object {$_.Sets.Count}).Count) 'Alt+Tab did not restore CPU Sets'}
 if($script:tick -eq 7){Check (-not @($script:priorities.Values|Where-Object {$_ -ne 'Normal'}).Count) 'Alt+Tab did not restore priorities'}
 $script:tick++;$script:clock.Elapsed.TotalSeconds=$script:tick;$script:clock.Elapsed.TotalMinutes=$script:tick/60.0
 if($script:tick -eq 9){$script:processes[40]=[pscustomobject]@{ProcessId=40;Name='msedge';StartTime='reused';Sets=@()}}
 if($script:stop -and $script:tick -eq 6){Stop-BnqqFocusSession|Out-Null}
}
function AssertRestored {
 Check ($script:service -eq 4) 'Service not restored after CPU failure/exit'
 Check (-not @($script:processes.Values|Where-Object {$_.Sets.Count}).Count) 'CPU Sets not restored'
 Check (-not @($script:priorities.Values|Where-Object {$_ -ne 'Normal'}).Count) 'Background priority not restored'
 Check (-not (Test-Path (Join-Path $temp 'focus-session.json'))) 'Controller marker leaked'
 $lock=Enter-BnqqStateLock;$lock.Dispose()
}
try{
 Initialize-BnqqCpuSets;$self=[Diagnostics.Process]::GetCurrentProcess()
 try{
  Assert-BnqqCpuProcessScope $self $self.Handle
  $scope=$script:BnqqCpuScope
  Check ([Bnqq.CpuSets]::OwnerSid($self.Handle) -ceq (Get-BnqqOwner)) 'Native owner SID mismatch'
  $script:BnqqCpuScope=[pscustomobject]@{SessionId=($scope.SessionId+1);Owner=$scope.Owner};MustThrow {Assert-BnqqCpuProcessScope $self $self.Handle}
  $script:BnqqCpuScope=[pscustomobject]@{SessionId=$scope.SessionId;Owner='foreign'};MustThrow {Assert-BnqqCpuProcessScope $self $self.Handle}
 }finally{$script:BnqqCpuScope=$scope;$self.Dispose()}
 Reset;MustThrow {Get-BnqqFocusPlan @('cs2')};MustThrow {Get-BnqqFocusPlan @('LAMZU Aurora')}
 $b=[pscustomobject]@{ProcessId=40;Name='msedge';StartTime='one';CpuMs=100}
 $c=$b|Select-Object *;$c.CpuMs=110;Check (@(Select-BnqqFocusBusy @($b) @($c) 5).Count -eq 0) 'Idle CPU selected'
 $c.CpuMs=1000;Check (@(Select-BnqqFocusBusy @($b) @($c) 5).Count -eq 1) 'Busy CPU not selected'
 $c.StartTime='reused';Check (@(Select-BnqqFocusBusy @($b) @($c) 5).Count -eq 0) 'PID reuse retained previous CPU sample'
 Check (@(Select-BnqqFocusBusy @($b) @($c) 0).Count -eq 0) 'Zero elapsed admitted'
 Reset;$b.StartTime='p40';$c.StartTime='p40'
 $state=[pscustomobject]@{Journal=$null;Journals=@();Touched=@{'40|p40'=$true};CpuSetIds=@(103);Epochs=0;Changes=0}
 Update-BnqqFocusEpoch $state @('msedge') 2 @($b) @($c) 5
 Check ($script:planReads -eq 0 -and $script:cpuWrites -eq 0) 'Already placed participant rebuilt plan or wrote scheduling'
 $b.StartTime='reused';$c.StartTime='reused';$script:processes[40].StartTime='reused'
 Update-BnqqFocusEpoch $state @('msedge') 2 @($b) @($c) 5
 Check ($script:planReads -eq 1 -and $state.Changes -eq 1) 'New PID lifetime was skipped as already placed'
 Restore-BnqqFocusEpoch $state
 Reset;$script:qa=$false;MustThrow {Invoke-BnqqFocusSession -Action run -Apps msedge};Check ($script:cpuWrites -eq 0 -and $script:serviceWrites -eq 0) 'QA gate wrote state'
 Reset;$r=Invoke-BnqqFocusSession -Action run -Apps msedge -PauseSearch
 Check ($r.Status -eq 'Restored' -and $r.Epochs -eq 2 -and $r.Changes -eq 6) 'Dynamic discovery, rate cap or focus epochs failed'
 Check $script:frameGuardChecked 'FrameBench guard not exercised';Check ($script:serviceWrites -eq 2) 'Service flapped on Alt+Tab';AssertRestored
 Reset;$script:failCpu=$true;MustThrow {Invoke-BnqqFocusSession -Action run -Apps msedge -PauseSearch};AssertRestored
 Reset;$script:failHealth=$true;MustThrow {Invoke-BnqqFocusSession -Action run -Apps msedge -PauseSearch};AssertRestored
 Reset;$script:stop=$true;$r=Invoke-BnqqFocusSession -Action run -Apps msedge;Check ($script:tick -eq 6) 'Cooperative stop failed';AssertRestored
 Reset;$r=Invoke-BnqqFocusSession -Action run -Apps msedge -Policy Priority
 Check ($r.Changes -eq 6 -and $script:priorityWrites -eq 12 -and $script:cpuWrites -eq 0 -and $script:planReads -eq 0) 'Priority mode changed placement or failed discovery/restore'
 AssertRestored
 Reset;$script:failPriority=$true;MustThrow {Invoke-BnqqFocusSession -Action run -Apps msedge -Policy Priority};AssertRestored
 Reset;$script:failHealth=$true;MustThrow {Invoke-BnqqFocusSession -Action run -Apps msedge -Policy Priority};AssertRestored
 Reset;MustThrow {Invoke-BnqqFocusSession -Apps Discord -Policy Priority};Check ($script:priorityWrites -eq 0) 'Voice process priority changed'
 Reset;$script:endTick=50;$script:quietAfter=15;$r=Invoke-BnqqFocusSession -Action run -Apps msedge -Policy Priority
 Check ($r.IdleRestores -eq 1 -and $script:cpuWrites -eq 0 -and $script:priorityWrites -eq 2*$r.Changes) 'Quiet release/cooldown failed'
 AssertRestored
 $before=[pscustomobject]@{ProcessId=40;Name='msedge';StartTime='fixed';CpuMs=100}
 $after=$before|Select-Object *;$after.CpuMs=110
 Check (Test-BnqqFocusQuiet @($before) @($after) 5) 'Quiet evidence rejected'
 $after.CpuMs=125;Check (-not (Test-BnqqFocusQuiet @($before) @($after) 5)) 'Hysteresis threshold lost'
 $after.CpuMs=90;Check (-not (Test-BnqqFocusQuiet @($before) @($after) 5)) 'Counter reset treated as quiet'
 $after.StartTime='new';Check (-not (Test-BnqqFocusQuiet @($before) @($after) 5)) 'New process treated as quiet'
 Check (-not (Test-BnqqFocusQuiet @() @() 31)) 'Stale sample admitted'
 Reset;Check ($null -eq (Get-BnqqFocusStatus)) 'Absent controller considered live'
 Write-BnqqAtomicJson @{Schema='BNQQ.Focus.1';Owner=(Get-BnqqOwner);Id='old';Controller=@{ProcessId=10;Name='cs2';StartTime='other'}} (Join-Path $temp 'focus-session.json')
 Check ($null -eq (Get-BnqqFocusStatus)) 'PID reuse accepted for controller';Assert-BnqqNoDynamicFocus
 $state=[pscustomobject]@{Journal=$null;Touched=@{};CpuSetIds=@(103);Epochs=64;Changes=0}
 $c=$b|Select-Object *;$c.CpuMs=1000;$b.StartTime='p40';$c.StartTime='p40'
 MustThrow {Update-BnqqFocusEpoch $state @('msedge') 2 @($b) @($c) 5}
 Check ($state.Changes -eq 0) 'Epoch bound changed processes'
 $state=[pscustomobject]@{Journal=[pscustomobject]@{Data=[pscustomobject]@{Entries=@(1..512)}};Touched=@{};CpuSetIds=@(103);Epochs=1;Changes=0}
 MustThrow {Update-BnqqFocusEpoch $state @('msedge') 2 @($b) @($c) 5};Check ($state.Changes -eq 0) '512 entry cap changed processes'
 $state=[pscustomobject]@{Journal=$null;Touched=@{};CpuSetIds=@(999);Epochs=0;Changes=0}
 MustThrow {Update-BnqqFocusEpoch $state @('msedge') 2 @($b) @($c) 5}
 ('PASS: focus '+$script:checks+' checks; measured selection, bounded discovery, Alt+Tab, PID reuse, WHEA, partial failure, cooperative stop and recovery')
}finally{if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}}
