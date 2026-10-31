#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\PlatformAudit.ps1')
$script:checks=0;$script:bcdFail=$false;$script:guardFail=$false;$script:cycle=$false;$script:parentFail=$false
function Check($v,$t){if(-not $v){throw $t};$script:checks++}
function Get-BnqqBootTimerSource {if($script:bcdFail){throw 'Denied fixture'};@('Windows Boot Loader','useplatformclock        Sim','disabledynamictick       No')}
function Get-BnqqDeviceGuardSource {if($script:guardFail){throw 'Unavailable fixture'};[pscustomobject]@{VirtualizationBasedSecurityStatus=2;SecurityServicesConfigured=@(1,2);SecurityServicesRunning=@(2)}}
function Get-BnqqDriverSource {
 param($Class)
 @([pscustomobject]@{DeviceID='ACPI\PNP0103\0';Name='Localized HPET';ConfigManagerErrorCode=22;Present=$true;PNPClass='System'},
 [pscustomobject]@{DeviceID='HID\MOUSE\0';Name='Mouse';Present=$true;PNPClass='Mouse'},
 [pscustomobject]@{DeviceID='HID\KEYBOARD\0';Name='Keyboard';Present=$true;PNPClass='Keyboard'},
 [pscustomobject]@{DeviceID='USB\HUB\0';Name='Hub';Present=$true;PNPClass='USB'},
 [pscustomobject]@{DeviceID='PCI\CONTROLLER\0';Name='Controller';Present=$true;PNPClass='USB';Service='USBXHCI'})
}
function Get-BnqqUsbParent {
 param($InstanceId)
 if($script:parentFail){throw 'Unknown parent fixture'}
 if($InstanceId -like 'HID\*'){return 'USB\HUB\0'}
 if($script:cycle){return 'HID\MOUSE\0'}
 return 'PCI\CONTROLLER\0'
}
$r=Get-BnqqTimerAudit
Check ($r.Status -eq 'Complete' -and $r.BootTimerOverrides[0].ExplicitOverridePresent -and $r.BootTimerOverrides[0].RawValue -eq 'Sim') 'Localized value was guessed or lost'
Check (-not $r.BootTimerOverrides[1].ExplicitOverridePresent -and $r.HpetDevices[0].ConfigManagerErrorCode -eq 22 -and -not $r.Changed) 'Absent entry/HPET state incorrect'
$script:bcdFail=$true;$r=Get-BnqqTimerAudit
Check ($r.Status -eq 'Partial' -and $null -eq $r.BootTimerOverrides[0].ExplicitOverridePresent) 'Access denied treated as default timers'
$r=Get-BnqqSecurityAudit
Check ($r.VbsStatus -eq 'Running' -and -not $r.Changed -and $r.AntiCheatCompatibility -eq 'NotTested') 'Security state wrong'
$script:guardFail=$true;$r=Get-BnqqSecurityAudit
Check ($r.VbsStatus -eq 'Unknown' -and $r.Status -eq 'Unavailable') 'Missing WMI invented security state'
$r=Get-BnqqUsbTopologyAudit
Check ($r.Status -eq 'Complete' -and $r.Peripherals.Count -eq 2 -and $r.Controllers.Count -eq 1) 'Topology grouping failed'
Check ($r.Controllers[0].LogicalInterfaces -eq 2 -and $r.ParentQueries -eq 3 -and -not $r.PollingRateMeasured -and -not $r.Changed) 'Cache/count/polling claim wrong'
$script:cycle=$true;$r=Get-BnqqUsbTopologyAudit
Check ($r.Status -eq 'Partial' -and @($r.Peripherals|Where-Object Status -eq 'Cycle').Count -eq 2) 'Topology cycle not bounded'
$script:parentFail=$true;$r=Get-BnqqUsbTopologyAudit
Check ($r.Status -eq 'Partial' -and -not $r.Controllers.Count) 'Unknown ancestry invented controller'
('PASS: platform '+$script:checks+' checks; timer localization, denied access, security, parent cache, cycles and unknown topology')
