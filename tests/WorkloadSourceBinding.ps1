#Requires -Version 5.1
# Real source hashing over temporary files; all hardware/power inputs are fixtures.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'lib\Core.ps1')
. (Join-Path $repo 'lib\Governance.ps1')
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temp=[IO.Path]::GetFullPath((Join-Path $base ('bnqq-source-binding-'+[guid]::NewGuid().ToString('N'))))
if(-not $temp.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture path'}
$script:BnqqRoot=$temp
function Get-CimInstance {
 param($ClassName,$ErrorAction)
 switch($ClassName){
  'Win32_OperatingSystem' {[pscustomobject]@{LastBootUpTime=[datetime]'2026-01-01T00:00:00Z';BuildNumber='fixture'}}
  'Win32_Processor' {[pscustomobject]@{Name='Fixture CPU';NumberOfLogicalProcessors=16}}
  'Win32_VideoController' {[pscustomobject]@{Name='Fixture GPU';DriverVersion='fixture'}}
  'Win32_PhysicalMemory' {[pscustomobject]@{Capacity=34359738368;ConfiguredClockSpeed=3200}}
  default {throw 'Unexpected hardware query'}
 }
}
function Get-BnqqPowerSnapshot {param($Scheme,$Setting='IDLEDISABLE');[pscustomobject]@{Scheme='fixture';Setting=$Setting;AC=0;DC=0}}
try{
 $lib=Join-Path $temp 'lib';[void][IO.Directory]::CreateDirectory($lib)
 foreach($name in @('Core.ps1','Governance.ps1','HeavyQA.ps1','StabilityLoad.cs','BackgroundBudget.ps1','ProcessSampling.ps1','ProcessTelemetry.cs')){[IO.File]::WriteAllText((Join-Path $lib $name),('fixture-'+$name))}
 $first=Get-BnqqConfigurationFingerprint -WorkloadOnly
 $native=Join-Path $lib 'ProcessTelemetry.cs';[IO.File]::AppendAllText($native,'changed-writer')
 $second=Get-BnqqConfigurationFingerprint -WorkloadOnly
 if($first -ceq $second){throw 'Native priority backend not bound to attestation'}
 [IO.File]::Delete($native)
 $refused=$false;try{Get-BnqqConfigurationFingerprint -WorkloadOnly|Out-Null}catch{$refused=$true}
 if(-not $refused){throw 'Missing priority backend did not invalidate fingerprint'}
 'PASS: workload attestation binds native backend and rejects incomplete sources; no hardware queries'
}finally{
 if([IO.Path]::GetFullPath($temp) -ne $temp -or -not $temp.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Cleanup path changed'}
 if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
}
