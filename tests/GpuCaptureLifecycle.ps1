$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\Core.ps1');. (Join-Path $root 'lib\FrameBench.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-gpu-capture-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$script:BnqqDataRoot=$temp;$script:starts=0;$script:stops=0
$oldFlag=$env:BNQQ_QA_PM_FAIL
$script:hardwareFault=$false;$script:captureFault=$false;$script:processReads=0
function Assert-BnqqWheaBaseline {if($script:hardwareFault){throw 'Recent WHEA fixture'}}
function Assert-BnqqPhaseHealth {param($Since);if($script:captureFault){throw 'New WHEA fixture'}}
$pm=Join-Path $temp 'presentmon-fixture.ps1'
@'
$position=[array]::IndexOf($args,'--output_file')
if($position -lt 0){throw 'Missing output path'}
[IO.File]::WriteAllText($args[$position+1],"fixture`r`n")
$global:LASTEXITCODE=0
if($env:BNQQ_QA_PM_FAIL -eq '1'){$global:LASTEXITCODE=3}
'@ | Set-Content -LiteralPath $pm -Encoding UTF8
function Check($ok,$message){if(-not $ok){throw $message}}
function MustThrow([scriptblock]$Code){$caught=$false;try{& $Code|Out-Null}catch{$caught=$true};Check $caught 'Expected capture refusal'}
function Get-Process {param($Name,$ErrorAction);$script:processReads++;return [pscustomobject]@{Id=42}}
function Get-BnqqHardware {return [pscustomobject]@{OS=@(@{Version='fixture';BuildNumber='1'});GPU=@(@{Name='fixture GPU';DriverVersion='1'});ObservedCPU=@(@{Name='fixture CPU';NumberOfCores=8;NumberOfLogicalProcessors=16})}}
function Get-BnqqProcessSnapshot {param($ProcessId);return @{ProcessId=$ProcessId;Name='cs2';Priority='Normal';Affinity='65535'}}
function Get-BnqqFrameStats {param($Path,$SkipSeconds,$ProcessId,$SwapChain);return [pscustomobject]@{Schema=2;DurationSeconds=10;Frames=2000}}
function Start-BnqqGpuRecorder {param($Seconds);$script:starts++;return [pscustomobject]@{LibraryHash=('A'*64)}}
function Stop-BnqqGpuRecorder {
 param($Recorder);$script:stops++
 return [pscustomobject]@{Schema=1;Provider='NVAPI';LibraryHash=$Recorder.LibraryHash;IntervalMs=500;DeviceWide=$true;Status='Complete';Error=$null;Samples=@(0..20|ForEach-Object {[pscustomobject]@{Seconds=($_*0.5);GpuPercent=80;TemperatureC=60;GraphicsMHz=1800;MemoryMHz=7000}})}
}
try {
 $env:BNQQ_QA_PM_FAIL='0'
 $r=Invoke-BnqqFrameBench -Seconds 10 -SkipSeconds 0 -Scenario fixture -SettingsHash same -ExperimentId fixture -Variant baseline -PresentMonPath $pm -GpuTelemetry
 Check ($r.GpuTelemetry.Status -eq 'Complete' -and $script:starts -eq 1 -and $script:stops -eq 1) 'Sampler lifecycle/metadata missing'
 Assert-BnqqGpuCaptureQuality $r
 $env:BNQQ_QA_PM_FAIL='1'
 MustThrow {Invoke-BnqqFrameBench -Seconds 10 -SkipSeconds 0 -Scenario fixture -SettingsHash same -ExperimentId fixture -Variant candidate -PresentMonPath $pm -GpuTelemetry}
 Check ($script:starts -eq 2 -and $script:stops -eq 2) 'Capture failure leaked sampler'
 $env:BNQQ_QA_PM_FAIL='0'
 $r=Invoke-BnqqFrameBench -Seconds 10 -SkipSeconds 0 -Scenario fixture -SettingsHash same -ExperimentId fixture -Variant baseline -PresentMonPath $pm
 Check (-not $r.Context.GpuInstrumentation -and -not $r.GpuTelemetry -and $script:starts -eq 2) 'Legacy capture unexpectedly instrumented'
 MustThrow {Invoke-BnqqFrameBench -Seconds 10 -SkipSeconds 0 -Scenario fixture -SettingsHash same -ExperimentId fixture -Variant baseline -PresentMonPath $pm -GpuTelemetry -Hotkey 'F11'}
 Check ($script:starts -eq 2) 'Hotkey refusal started worker'
 $script:hardwareFault=$true;$reads=$script:processReads
 MustThrow {Invoke-BnqqFrameBench -Seconds 10 -SkipSeconds 0 -Scenario fixture -SettingsHash same -ExperimentId fixture -Variant baseline -PresentMonPath $pm -GpuTelemetry}
 Check ($script:starts -eq 2 -and $script:processReads -eq $reads) 'WHEA refusal opened game or started sampler'
 $script:hardwareFault=$false;$script:captureFault=$true
 $before=@(Get-ChildItem $temp -Recurse -Filter result.json).Count
 MustThrow {Invoke-BnqqFrameBench -Seconds 10 -SkipSeconds 0 -Scenario fixture -SettingsHash same -ExperimentId fixture -Variant baseline -PresentMonPath $pm -GpuTelemetry}
 Check ($script:starts -eq 3 -and $script:stops -eq 3) 'New hardware incident leaked GPU sampler'
 Check (@(Get-ChildItem $temp -Recurse -Filter result.json).Count -eq $before) 'Hardware-incident capture published a successful result'
 'PASS: capture metadata, GPU sampler cleanup on success/failure, no default instrumentation and hotkey-window refusal'
}finally{
 $env:BNQQ_QA_PM_FAIL=$oldFlag
 $full=[IO.Path]::GetFullPath($temp)
 if(-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
 [IO.Directory]::Delete($full,$true)
}
