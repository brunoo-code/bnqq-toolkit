#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\DriverAudit.ps1')
$script:failClass='';$script:checks=0
function Check($ok,$text){if(-not $ok){throw $text};$script:checks++}
function Get-BnqqDriverSource {
 param($Class)
 if($Class -eq $script:failClass -or $script:failClass -eq '*'){throw 'Provider unavailable fixture'}
 switch($Class){
  'Win32_PnPEntity' {
   [pscustomobject]@{DeviceID='PCI\NET\ONE';Name='Fixture NIC';PNPClass='Net';Present=$true;Status='OK';ConfigManagerErrorCode=0;Service='fixture'}
   [pscustomobject]@{DeviceID='PCI\GPU\ONE';Name='Fixture GPU';PNPClass='Display';Present=$true;Status='Error';ConfigManagerErrorCode=43;Service='absent'}
  }
  'Win32_PnPSignedDriver' {
   [pscustomobject]@{DeviceID='pci\net\one';DriverProviderName='Vendor A';DriverVersion='1.2';InfName='one.inf';IsSigned=$true;Signer='Fixture'}
   [pscustomobject]@{DeviceID='PCI\NET\ONE';DriverProviderName='Vendor B';DriverVersion='2.3';InfName='two.inf';IsSigned=$null;Signer=$null}
  }
  'Win32_SystemDriver' {
   [pscustomobject]@{Name='fixture';PathName='\SystemRoot\System32\drivers\fixture.sys';State='Running';DisplayName='Fixture';StartMode='Manual'}
   [pscustomobject]@{Name='stopped';PathName='C:\Windows\stopped.sys';State='Stopped'}
  }
 }
}
Check ((Get-BnqqDriverModuleName '"C:\Program Files\Vendor\foo.sys"') -eq 'foo.sys') 'Quoted module path failed'
Check ((Get-BnqqDriverModuleName '"C:\Program Files\Vendor\foo bar.sys" /arg') -eq 'foo bar.sys') 'Filename with spaces was truncated'
Check ($null -eq (Get-BnqqDriverModuleName 'unknown')) 'Unknown path invented module'
Check ($null -eq (Get-BnqqDriverModuleName 'one.sys two.sys')) 'Ambiguous path picked arbitrary module'
$r=Get-BnqqDriverAudit
Check ($r.Status -eq 'Complete' -and $r.Devices.Count -eq 2 -and $r.RunningModules.Count -eq 1) 'Inventory failed'
$nic=@($r.Devices|Where-Object Class -eq 'Net')[0]
Check ($nic.PackageMatch -eq 'Multiple' -and $nic.Packages.Count -eq 2) 'Ambiguous package silently selected'
Check ($nic.Packages[0].SignedReported -eq $true -and $null -eq $nic.Packages[1].SignedReported) 'Unknown signature coerced to false'
Check ($nic.ServiceModules[0].Module -eq 'fixture.sys' -and $nic.ServiceMatch -eq 'Single') 'Exact service join failed'
Check ($r.ReportedDeviceProblems -eq 1 -and $r.DpcAttribution -eq 'NotMeasured' -and -not $r.RecommendedDeviceChanges.Count) 'Problem code became latency verdict'
$script:failClass='Win32_PnPSignedDriver';$r=Get-BnqqDriverAudit
Check ($r.Status -eq 'Partial' -and $r.Devices.Count -eq 2 -and $r.Errors.Count -eq 1 -and $r.Devices[0].PackageMatch -eq 'Missing') 'CIM failure erased remaining inventory'
$script:failClass='*';$r=Get-BnqqDriverAudit
Check ($r.Status -eq 'Unavailable' -and $r.Errors.Count -eq 3) 'All-provider failure invented hardware'
('PASS: driver inventory '+$script:checks+' checks; partial sources, ambiguity, unknown signature and no latency verdict')
