#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
foreach($n in @('Core','BackgroundBudget','NetworkSession','CompetitionSession')){. (Join-Path $root ('lib\'+$n+'.ps1'))}
$script:checks=0;$script:vendor='10DE';$script:cimFail=$false;$script:ran=$null;$script:ready=$true
function Check($v,$m){if(-not $v){throw $m};$script:checks++}
function MustThrow([scriptblock]$c){$hit=$false;try{& $c|Out-Null}catch{$hit=$true};Check $hit 'Expected competition refusal'}
function Get-CimInstance {
 param($ClassName,$OperationTimeoutSec,$ErrorAction)
 if($script:cimFail){throw 'CIM unavailable fixture'}
 if($ClassName -eq 'Win32_VideoController'){return [pscustomobject]@{Name='Fixture GPU';DriverVersion='1.2';PNPDeviceID=('PCI\VEN_'+$script:vendor+'&DEV_0000')}}
 if($ClassName -eq 'Win32_Processor'){return [pscustomobject]@{Name='CPU fixture';NumberOfCores=8;NumberOfLogicalProcessors=16}}
 throw 'No SMBIOS fallback allowed'
}
function Get-BnqqFocusPlan {
 param($Apps,$Policy,$PauseSearch,$DeferMaintenance)
 foreach($app in $Apps){if($app -notin (Get-BnqqBudgetAllowedApps)){throw 'Forbidden app fixture'}}
 [pscustomobject]@{Apps=@($Apps);Policy=$Policy;Maintenance=@{RequiresAdmin=[bool]$PauseSearch}}
}
function Get-BnqqReadiness {return [pscustomobject]@{WorkloadReady=$script:ready}}
function Invoke-BnqqFocusSession {
 param($Action,$Apps,$Policy,$UploadApps,$UploadKbps,$PauseSearch,$DeferMaintenance,$Game,$MaxMinutes)
 if(-not $script:ready){throw 'Real focus gate fixture'}
 $script:ran=[pscustomobject]@{Action=$Action;Apps=@($Apps);Policy=$Policy;UploadApps=@($UploadApps);Rate=$UploadKbps;Game=$Game;MaxMinutes=$MaxMinutes}
 return $script:ran
}
foreach($pair in @(@('10DE','NVIDIA'),@('1002','AMD'),@('8086','Intel'),@('FFFF','Unknown'))){
 $script:vendor=$pair[0];$p=Invoke-BnqqCompetitionSession
 Check ($p.Hardware.Gpu[0].ObservedPciVendor -eq $pair[1] -and -not $p.Hardware.Gpu[0].GpuWritesInThisSession) 'GPU vendor policy wrong'
 Check ($p.Focus.Policy -eq 'Priority' -and $p.Focus.Apps.Count -eq 4 -and -not $p.RequiresAdmin -and -not $script:ran) 'Default preview started work or selected implicit admin changes'
}
$script:cimFail=$true;$p=Invoke-BnqqCompetitionSession
Check ($p.Hardware.Status -eq 'Partial' -and $p.Hardware.Errors.Count -eq 2 -and -not $p.Hardware.Gpu.Count) 'Failed inventory invented hardware'
$script:cimFail=$false
$r=Invoke-BnqqCompetitionSession -Action run -Apps msedge -UploadApps OneDrive.exe -UploadKbps 768 -Game VALORANT-Win64-Shipping.exe -MaxMinutes 10
Check ($r.Policy -eq 'Priority' -and $r.Apps.Count -eq 1 -and $r.Rate -eq 768 -and $r.Game -eq 'VALORANT-Win64-Shipping.exe') 'Single-controller parameters lost'
$script:ready=$false;MustThrow {Invoke-BnqqCompetitionSession -Action run}
MustThrow {Invoke-BnqqCompetitionSession -Apps Discord}
MustThrow {Invoke-BnqqCompetitionSession -UploadApps cs2.exe}
('PASS: competition '+$script:checks+' checks; NVIDIA/AMD/Intel/unknown, no vendor writes, partial CIM, policy delegation and readiness refusal')
