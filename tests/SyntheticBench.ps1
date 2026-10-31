#Requires -Version 5.1
# Native correctness fixture only; synthetic workers are mocked and never started.
$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($name in @('Core','SyntheticBench')){. (Join-Path $script:BnqqRoot ('lib\'+$name+'.ps1'))}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-synthetic-'+[guid]::NewGuid().ToString('N'))
$script:BnqqDataRoot=$temp;$script:checks=0
function Check($ok,$text){if(-not $ok){throw $text};$script:checks++}
function MustThrow([scriptblock]$Code){$hit=$false;try{& $Code|Out-Null}catch{$hit=$true};Check $hit 'Expected synthetic refusal'}
function Reset {
 $script:qa=$true;$script:game=$false;$script:newFault=$false;$script:failStart=$false;$script:tick=0;$script:starts=0;$script:stops=0;$script:disposed=0
 $script:clock=[pscustomobject]@{Elapsed=[pscustomobject]@{TotalSeconds=0}}
}
function Get-BnqqSyntheticLogicalProcessors {return 16}
function Assert-BnqqWheaBaseline {if(-not $script:qa){throw 'Recent WHEA fixture'}}
function Assert-BnqqSyntheticNoGame {if($script:game){throw 'Game active fixture'}}
function Assert-BnqqPhaseHealth {param($Since);if($script:newFault -and $script:tick -ge 2){throw 'WHEA during load fixture'}}
function New-BnqqSyntheticClock {return $script:clock}
function Get-BnqqSyntheticHostSample {[pscustomobject]@{CpuMs=($script:tick*100);WorkingSetBytes=1000000}}
function New-BnqqSyntheticLoad {
 $load=[pscustomobject]@{Running=$false;Failed=$false;ElapsedSeconds=0;Passes=0}
 $load|Add-Member ScriptMethod Start {param($Threads,$Seconds,$Duty,$Cycle,$Memory);$script:starts++;$this.Running=$true;if($script:failStart){throw 'Partial start fixture'}}
 $load|Add-Member ScriptMethod Stop {$script:stops++;$this.Running=$false}
 $load|Add-Member ScriptMethod Dispose {$this.Stop();$script:disposed++}
 $script:fake=$load;return $load
}
function Start-Sleep {param($Milliseconds);$script:tick++;$script:clock.Elapsed.TotalSeconds=$script:tick;$script:fake.ElapsedSeconds=$script:tick;$script:fake.Passes+=10}
try {
 Add-Type -Path (Join-Path $script:BnqqRoot 'lib\SyntheticLoad.cs')
 Check ([Bnqq.SyntheticLoad]::VerifyKernelFixture($false)) 'Native verified kernel failed'
 Check (-not [Bnqq.SyntheticLoad]::VerifyKernelFixture($true)) 'Native corruption went undetected'
 MustThrow {[Bnqq.SyntheticLoad]::Validate(17,30,50,100,4)}
 MustThrow {[Bnqq.SyntheticLoad]::Validate(4,121,50,100,4)}
 MustThrow {[Bnqq.SyntheticLoad]::Validate(4,30,100,100,4)}
 $native=New-Object Bnqq.SyntheticLoad;$native.Dispose();$native.Dispose()
 Check (-not $native.Running -and $native.Passes -eq 0) 'Unstarted native disposal failed'
 Reset;$p=Invoke-BnqqSyntheticBench
 Check ($p.Threads -eq 4 -and $p.TotalScratchMiB -eq 16 -and -not $p.PrefireEquivalent -and $script:starts -eq 0) 'Plan started worker or claimed parity'
 [void][IO.Directory]::CreateDirectory($temp)
 $reference=Join-Path $temp 'frame-reference.json'
 @{Schema=2;Started='fixture';Context=@{Scenario='prefire-fixture'};Stats=@{Schema=2;AvgFps=318;Low1Fps=91;Low01Fps=63;P99Ms=8.8;JitterMs=2.1}}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $reference
 $p=Invoke-BnqqSyntheticBench -ReferenceFile $reference
 Check ($p.Reference.Scenario -eq 'prefire-fixture' -and $p.Reference.ObservedFrameMetrics.AvgFps -eq 318 -and -not $p.Reference.UsedToSetLoadParameters) 'Reference was lost or falsely calibrated'
 Reset;$script:qa=$false;MustThrow {Invoke-BnqqSyntheticBench -Action run -Seconds 3};Check ($script:starts -eq 0) 'WHEA guard started worker'
 Reset;$script:game=$true;MustThrow {Invoke-BnqqSyntheticBench -Action run -Seconds 3};Check ($script:starts -eq 0) 'Game guard started worker'
 Reset;$r=Invoke-BnqqSyntheticBench -Action run -Seconds 3 -IdleTailSeconds 2
 Check ($r.Completed -and $r.Samples.Count -eq 3 -and $script:tick -eq 5 -and $script:disposed -eq 1 -and -not $r.HeavyQaCertificate) 'Success/idle tail/cleanup failed'
 Check ([math]::Abs($r.Samples[0].HostMachineCpuPercent-.625) -lt .00001) 'CPU meter denominator wrong'
 Check ((Get-Content $r.ResultFile -Raw|ConvertFrom-Json).Verdict -eq 'COMPLETED_NO_DETECTED_ERROR') 'Result not durable'
 Reset;$script:newFault=$true;MustThrow {Invoke-BnqqSyntheticBench -Action run -Seconds 4}
 Check ($script:disposed -eq 1 -and -not $script:fake.Running -and $script:tick -eq 2) 'WHEA did not stop/cleanup promptly'
 Reset;$script:failStart=$true;MustThrow {Invoke-BnqqSyntheticBench -Action run -Seconds 3}
 Check ($script:disposed -eq 1 -and -not $script:fake.Running) 'Partial start leaked worker'
 $lock=Enter-BnqqStateLock;$lock.Dispose()
 $results=@(Get-ChildItem $temp -Recurse -Filter '*.json'|ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json})
 Check (@($results|Where-Object Verdict -eq 'FAILED').Count -eq 2) 'Failures were published as successful measurements'
 ('PASS: synthetic '+$script:checks+' checks; C# kernel fixture, bounds, no native load, WHEA/game refusal, success/fault cleanup and durable results')
}finally{
 $full=[IO.Path]::GetFullPath($temp);$allowedRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if(-not $full.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $full -Leaf) -notlike 'bnqq-synthetic-*'){throw 'Unsafe synthetic fixture cleanup'}
 if([IO.Directory]::Exists($full)){[IO.Directory]::Delete($full,$true)}
}
