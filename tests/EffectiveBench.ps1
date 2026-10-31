# Fixtures only; no game, task, power, registry or scheduling changes.
$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($name in @('Core','FrameBench','EffectiveBench')){. (Join-Path $script:BnqqRoot ('lib\'+$name+'.ps1'))}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-effective-test-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Check {param($Ok,$Why);if(-not $Ok){throw $Why};$script:checks++}
function Throws {param([scriptblock]$Code,$Why);$hit=$false;try{& $Code|Out-Null}catch{$hit=$true};Check $hit $Why}
try{
    [void][IO.Directory]::CreateDirectory($temp)
    $baseline=[pscustomobject]@{Schema=2;Variant='baseline';Started='2026-01-01T00:00:00Z';PresentMonHash='same';Context=[pscustomobject]@{ExperimentId='fixture';Scenario='same';SettingsHash='gfx';Game='cs2.exe'};Process=[pscustomobject]@{Priority='AboveNormal';Affinity='21845'};Stats=[pscustomobject]@{AvgFps=200;Low1Fps=100;Low01Fps=80;P99Ms=10;P999Ms=15;JitterMs=2;Metric='MsBetweenPresents';Runtime='Other';SkipSeconds=5}}
    $candidate=$baseline|ConvertTo-Json -Depth 8|ConvertFrom-Json
    $candidate.Variant='candidate';$candidate.Stats.Low1Fps=110;$candidate.Stats.Low01Fps=88;$candidate.Stats.P99Ms=9;$candidate.Stats.JitterMs=1.8
    $candidate.Process.Priority='Normal';$candidate.Process.Affinity='65535'
    $r=Compare-BnqqFramePair $baseline $candidate
    Check ($r.Effective -eq $null -and $r.Verdict -eq 'EXPLORATORY_ONE_PAIR') 'One pair must never declare effectiveness'
    Check ($r.Metrics.Count -eq 6) 'All six requested metrics exported'
    Check ([math]::Abs(($r.Metrics|Where-Object Metric -eq 'Low1Fps').DeltaPercent-10) -lt .0001) '1% low delta'
    Check ([math]::Abs(($r.Metrics|Where-Object Metric -eq 'Low01Fps').DeltaPercent-10) -lt .0001) '0.1% low delta'
    Check (($r.Metrics|Where-Object Metric -eq 'P99Ms').Better -eq 'candidate') 'Lower p99 is better'
    Check (($r.Metrics|Where-Object Metric -eq 'JitterMs').Better -eq 'candidate') 'Lower jitter is better'
    Check ($r.BaselineProcess.Affinity -eq '21845' -and $r.CandidateProcess.Affinity -eq '65535') 'Treatment state preserved, never relabel original as stock'
    $candidate.Context.SettingsHash='different'
    Throws {Compare-BnqqFramePair $baseline $candidate} 'Changed graphics context refused'
    $candidate.Context.SettingsHash='gfx';$candidate|Add-Member CaptureIntegrity @{Passed=$false}
    Throws {Compare-BnqqFramePair $baseline $candidate} 'Failed guard cannot yield comparison'
    $candidate.CaptureIntegrity.Passed=$true;$candidate.Stats.JitterMs=[double]::NaN
    Throws {Compare-BnqqFramePair $baseline $candidate} 'Non-finite values refused'
    $file=Join-Path $temp 'reference.json';Write-BnqqAtomicJson $baseline $file
    Check ((Read-BnqqBaseline $file).Context.ExperimentId -eq 'fixture') 'Reference reader'
    $preview=Invoke-BnqqEffectiveBench -BaselineFile $file -DryRun
    Check ($preview.PlannedPriority -eq 'Normal' -and $preview.Effective -eq $null) 'Dry-run only reads reference'
    Throws {Invoke-BnqqEffectiveBench -BaselineFile $file} 'Explicit process mutation opt-in required'
    Write-BnqqAtomicJson @('Started recording.',$baseline) $file
    Throws {Read-BnqqBaseline $file} 'Mixed console stdout is not a reference'
    function Get-ScheduledTask {param($TaskName);return $script:tasks}
    function Get-CimInstance {param($ClassName,$Filter);return $script:processes}
    $script:tasks=@();$script:processes=@()
    Assert-BnqqNoInterferingWatcher;Check $true 'No watchers accepted'
    $script:tasks=@([pscustomobject]@{TaskName='BNQQ Game Watcher';State='Running'})
    Throws {Assert-BnqqNoInterferingWatcher} 'Running legacy task rejected'
    $script:tasks[0].State='Ready'
    Throws {Assert-BnqqNoInterferingWatcher} 'Enabled task could restart mid-capture'
    $script:tasks[0].State='Disabled'
    Assert-BnqqNoInterferingWatcher;Check $true 'Disabled task accepted'
    $script:processes=@([pscustomobject]@{ProcessId=999;CommandLine='powershell.exe -NoProfile -File "C:\tool\bnqq-watch.ps1"'})
    Throws {Assert-BnqqNoInterferingWatcher} 'Direct watcher outside scheduler rejected'
    $script:processes[0].CommandLine='powershell.exe -File "C:\tool\bnqq.ps1" watch -WatcherAction run'
    Throws {Assert-BnqqNoInterferingWatcher} 'Main CLI watcher detected'
    $script:processes=@()
    function Get-BnqqTopology {return @([pscustomobject]@{Group=0;Mask=3},[pscustomobject]@{Group=0;Mask=12})}
    Check ((Get-BnqqFullTopologyMask) -eq 15) 'Full topology includes SMT siblings'
    # Test the actual guard job lifecycle against isolated read-only fixture adapters.
    $fixtureRoot=Join-Path $temp 'fixture';$fixtureLib=Join-Path $fixtureRoot 'lib'
    [void][IO.Directory]::CreateDirectory($fixtureLib)
    Copy-Item -LiteralPath (Join-Path $script:BnqqRoot 'lib\Core.ps1') -Destination (Join-Path $fixtureLib 'Core.ps1')
    Set-Content (Join-Path $fixtureLib 'RuntimeLatency.ps1') 'function Get-BnqqProcessSnapshot {param($ProcessId);return $Expected}'
    Set-Content (Join-Path $fixtureLib 'EffectiveBench.ps1') 'function Assert-BnqqNoInterferingWatcher {}'
    $originalRoot=$script:BnqqRoot;$script:BnqqRoot=$fixtureRoot
    $expected=[pscustomobject]@{ProcessId=1;Name='fixture';StartTime='fixture';Priority='Normal';Affinity='15'}
    $guard=$null
    try{
        $guard=Start-BnqqCaptureGuard $expected $temp
        $integrity=Stop-BnqqCaptureGuard $guard;$guard=$null
        Check ($integrity.Passed -and $integrity.Checks -ge 2) 'Guard startup handshake, read-only polling and cooperative stop'
    }finally{
        if($guard){Stop-Job $guard.Job -ErrorAction SilentlyContinue;Remove-Job $guard.Job -Force -ErrorAction SilentlyContinue}
        $script:BnqqRoot=$originalRoot
    }
    Write-Host ('PASS: '+$checks+' effective-bench checks; no tuning applied.')
}finally{
    $resolved=[IO.Path]::GetFullPath($temp)
    if($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'bnqq-effective-test-*'){
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
