$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\Core.ps1');. (Join-Path $root 'lib\FrameBench.ps1')
function Check($ok,$message){if(-not $ok){throw $message}}
function MustThrow([scriptblock]$Code){$caught=$false;try{& $Code|Out-Null}catch{$caught=$true};Check $caught 'Expected telemetry rejection'}
function Capture {
 return [pscustomobject]@{Context=[pscustomobject]@{GpuInstrumentation=[pscustomobject]@{Provider='NVAPI';IntervalMs=500;LibraryHash=('A'*64)}};Stats=[pscustomobject]@{DurationSeconds=60};GpuTelemetry=[pscustomobject]@{Schema=1;Provider='NVAPI';LibraryHash=('A'*64);IntervalMs=500;DeviceWide=$true;Status='Complete';Error=$null;Samples=@(0..120|ForEach-Object {[pscustomobject]@{Seconds=($_*0.5);GpuPercent=90;TemperatureC=60;GraphicsMHz=1800;MemoryMHz=7000;Pstate=0}})}}
}
$c=Capture;Assert-BnqqGpuCaptureQuality $c
$c.GpuTelemetry.Status='Failed';MustThrow {Assert-BnqqGpuCaptureQuality $c}
$c=Capture;$c.GpuTelemetry.LibraryHash='B'*64;MustThrow {Assert-BnqqGpuCaptureQuality $c}
$c=Capture;$c.GpuTelemetry.Samples[3].Seconds=100;MustThrow {Assert-BnqqGpuCaptureQuality $c}
$c=Capture;$c.GpuTelemetry.Samples[2].GpuPercent=101;MustThrow {Assert-BnqqGpuCaptureQuality $c}
$c=Capture;$c.GpuTelemetry.Samples[2].GraphicsMHz='NaN';MustThrow {Assert-BnqqGpuCaptureQuality $c}
$c=Capture;$c.GpuTelemetry.Samples=@($c.GpuTelemetry.Samples|Select-Object -First 10);MustThrow {Assert-BnqqGpuCaptureQuality $c}
$c=Capture;$c.Context=[pscustomobject]@{};MustThrow {Assert-BnqqGpuCaptureQuality $c}
Assert-BnqqGpuCaptureQuality ([pscustomobject]@{Context=[pscustomobject]@{Scenario='legacy'}})
'PASS: instrumented telemetry status, library identity, chronology, finite values, utilization, coverage and legacy compatibility'
