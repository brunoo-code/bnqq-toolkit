$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($name in @('Core','GpuDriver')){. (Join-Path $script:BnqqRoot ('lib\'+$name+'.ps1'))}
# Compile the native bridge on CI, without loading NVAPI or changing a driver.
Add-Type -Path @((Join-Path $script:BnqqRoot 'lib\NvidiaDriver.cs'),(Join-Path $script:BnqqRoot 'lib\NvidiaTelemetry.cs'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-gpu-'+[guid]::NewGuid().ToString('N'))
$script:BnqqDataRoot=$temp;$script:writes=0;$script:qa=$true;$script:admin=$true;$script:partial=$false;$script:health=$true;$script:vendor=$true;$script:open=$false;$script:globalValue=5
$script:state=[pscustomobject]@{Application='C:\fixture\cs2.exe';Profile='Counter-strike 2';DriverVersion=62101;LibraryHash=('A'*64);Applications=@('cs2.exe','csgos2.exe');Found=$true;LocalOverride=$false;Value=5;Location=1;CurrentPredefined=0;Available=@(0,1,2,3,4,5);CapabilityStatus=0}
function Check($ok,$message){if(-not $ok){throw $message}}
function MustThrow([scriptblock]$Code){$caught=$false;try{& $Code|Out-Null}catch{$caught=$true};Check $caught 'Expected refusal'}
function Get-BnqqGpuSupport {return [pscustomobject]@{Status=$(if($script:vendor){'NvidiaAvailable'}else{'Unavailable'});Gpus=@([pscustomobject]@{Name='fixture GPU'})}}
function Resolve-BnqqGpuGamePath {param($Game,$Path);return 'C:\fixture\cs2.exe'}
function Get-BnqqGpuState {param($Application);return ($script:state|Select-Object *)}
function Assert-BnqqHeavyQa {if(-not $script:qa){throw 'QA refusal fixture'}}
function Test-BnqqAdmin {return $script:admin}
function Write-BnqqNightLog {param($Stage,$Message)}
function Assert-BnqqPhaseHealth {param($Since);if(-not $script:health){throw 'New WHEA fixture'}}
function Get-Process {param($Name,$ErrorAction);if($script:open){return [pscustomobject]@{Id=10}}}
function Set-BnqqGpuState {
 param($Expected,$Mode,$Before)
 Check (Test-BnqqSameValue $script:state $Expected) 'Stale native snapshot'
 $journals=@(Get-ChildItem (Join-Path $temp 'nvidia-journals') -Filter '*.json'|ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json}|Where-Object Status -ne 'Restored')
 Check ($journals.Count -eq 1 -and $journals[0].Schema -eq 'BNQQ.Nvidia.1') 'Missing atomic backup before driver write'
 $script:writes++
 if($Mode -eq 'max'){$script:state.LocalOverride=$true;$script:state.Value=1;$script:state.Location=0}
 elseif($Before.LocalOverride){$script:state.Value=$Before.Value;$script:state.LocalOverride=$true;$script:state.Location=0}
 else{$script:state.Value=$script:globalValue;$script:state.LocalOverride=$false;$script:state.Location=1}
 if($script:partial){$script:partial=$false;throw 'Failure after native save fixture'}
}
try {
 $script:vendor=$false;Check ((Get-BnqqGpuPlan).Status -eq 'Unsupported') 'AMD/Intel must not receive NVIDIA fallback';$script:vendor=$true
 Check ((Get-BnqqGpuPlan).WouldChange -and $script:writes -eq 0) 'Plan must not write'
 $script:state.Value=1;$script:qa=$false
 Check ((Invoke-BnqqGpuProfile -Action apply).Status -eq 'AlreadyMaxPerformance' -and $script:writes -eq 0) 'Inherited max must be no-op without QA stress'
 $script:state.Value=5;MustThrow {Invoke-BnqqGpuProfile -Action apply};$script:qa=$true
 $script:admin=$false;MustThrow {Invoke-BnqqGpuProfile -Action apply};$script:admin=$true
 $script:open=$true;MustThrow {Invoke-BnqqGpuProfile -Action apply};$script:open=$false
 $script:state.Applications+=@('other-game.exe');MustThrow {Get-BnqqGpuPlan};$script:state.Applications=@('cs2.exe','csgos2.exe')
 Check ($script:writes -eq 0) 'Guard caused a write'
 $r=Invoke-BnqqGpuProfile -Action apply
 Check ($r.Status -eq 'Applied' -and $script:state.LocalOverride -and $script:state.Value -eq 1) 'Native profile not applied'
 MustThrow {Invoke-BnqqGpuProfile -Action apply}
 $script:qa=$false;$script:admin=$false
 Invoke-BnqqGpuProfile -Action restore -File $r.Journal|Out-Null
 Check (-not $script:state.LocalOverride -and $script:state.Value -eq 5) 'Original inherited setting not restored'
 $count=$script:writes;Restore-BnqqGpuProfile $r.Journal|Out-Null;Check ($script:writes -eq $count) 'Not idempotent'
 $script:qa=$true;$script:admin=$true;$script:partial=$true
 MustThrow {Invoke-BnqqGpuProfile -Action apply}
 Check (-not $script:state.LocalOverride) 'Partial native save not rolled back'
 $script:health=$false;MustThrow {Invoke-BnqqGpuProfile -Action apply};$script:health=$true
 Check (-not $script:state.LocalOverride) 'WHEA did not trigger rollback'
 $script:state.LocalOverride=$true;$script:state.Value=3;$script:state.Location=0
 $r=Invoke-BnqqGpuProfile -Action apply;Restore-BnqqGpuProfile $r.Journal|Out-Null
 Check ($script:state.LocalOverride -and $script:state.Value -eq 3) 'Original explicit override not restored'
 $script:state.LocalOverride=$false;$script:state.Value=5;$script:state.Location=1
 $r=Invoke-BnqqGpuProfile -Action apply;$count=$script:writes
 $script:state.Value=2;MustThrow {Restore-BnqqGpuProfile $r.Journal};Check ($script:writes -eq $count) 'External override overwritten'
 $script:state.Value=1;$script:state.DriverVersion=62102;MustThrow {Restore-BnqqGpuProfile $r.Journal};$script:state.DriverVersion=62101
 $script:globalValue=2;Restore-BnqqGpuProfile $r.Journal|Out-Null
 Check (-not $script:state.LocalOverride -and $script:state.Value -eq 2) 'External global setting overwritten during restore'
 $j=Get-Content $r.Journal -Raw|ConvertFrom-Json;$j.Owner='wrong';Write-BnqqAtomicJson $j $r.Journal;MustThrow {Restore-BnqqGpuProfile $r.Journal}
 $j.Owner=Get-BnqqOwner;$j.Before.Application='C:\fixture\other.exe';Write-BnqqAtomicJson $j $r.Journal;MustThrow {Restore-BnqqGpuProfile $r.Journal}
 'PASS: native bridge compiles; vendor gating, no-op, scope, admin/QA, backup, apply, partial save, WHEA rollback, original override/inheritance, external changes, owner and target checks'
}finally{
 $full=[IO.Path]::GetFullPath($temp)
 if(-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
 if([IO.Directory]::Exists($full)){[IO.Directory]::Delete($full,$true)}
}
