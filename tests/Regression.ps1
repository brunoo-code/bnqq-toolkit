#Requires -Version 5.1
# No registry, service, scheduled task, game or power changes. All mutation adapters are mocked.
$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
$script:BnqqDataRoot=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-tests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:BnqqDataRoot)
$script:checks=0
function Check {param($Condition,[string]$Message);if(-not $Condition){throw ('FAIL: '+$Message)};$script:checks++}
function Throws {param([scriptblock]$Code,[string]$Message);$hit=$false;try{& $Code | Out-Null}catch{$hit=$true};Check $hit $Message}
try {
    foreach($file in @('Core','Governance','Topology','Diagnostics','Optimize','Apps','RuntimeLatency','Watcher','HeavyQA','FrameBench')){. (Join-Path $script:BnqqRoot ('lib\'+$file+'.ps1'))}
    foreach($file in @(Get-ChildItem $script:BnqqRoot -Recurse -File -Filter '*.ps1'|Where-Object {$_.FullName -notmatch '\\(reports|backups|dist|build)\\'})){
        $t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$t,[ref]$e)
        Check ($e.Count -eq 0) ('Parser '+$file.Name)
    }
    $file=Join-Path $script:BnqqDataRoot 'atomic.json'
    Write-BnqqAtomicJson @{Value='primeiro'} $file
    Write-BnqqAtomicJson @{Value='ação'} $file
    Check ((Get-Content $file -Raw -Encoding UTF8|ConvertFrom-Json).Value -eq 'ação') 'Atomic replacement preserves UTF8'
    $lock=Enter-BnqqStateLock
    try{Throws {Enter-BnqqStateLock} 'Concurrent writer excluded'}finally{$lock.Dispose()}

    # In-memory registry adapter: real journal/validation/recovery runs against these snapshots.
    $script:state=[pscustomobject]@{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR';Name='AllowGameDVR';KeyExisted=$true;Existed=$true;Kind='DWord';Value=1}
    function Get-RegSnapshot {param($Path,$Name);return ($script:state|Select-Object *)}
    function Set-BnqqRegistrySnapshot {
        param($Snapshot)
        if($script:assertPrepared){
            $disk=Get-Content $script:currentJournal.File -Raw -Encoding UTF8|ConvertFrom-Json
            Check ($disk.Entries[-1].Status -in @('Prepared','Failed')) 'Write-ahead is durable before target write'
        }
        $script:state=$Snapshot|Select-Object *
        if($script:failAfterWrite){$script:failAfterWrite=$false;throw 'Injected interruption after mutation'}
    }
    function New-FixtureOperation {
        $before=$script:state|Select-Object *;$after=$before|Select-Object *;$after.Value=0
        return [pscustomobject]@{Kind='Registry';Before=$before;After=$after}
    }
    $script:currentJournal=New-BnqqJournal 'regression';$script:assertPrepared=$true
    $op=New-FixtureOperation
    Invoke-BnqqJournalOperation $script:currentJournal $op
    Check ($script:state.Value -eq 0) 'Applied state'
    $script:assertPrepared=$false
    Restore-BnqqJournal $script:currentJournal.File|Out-Null
    Check ($script:state.Value -eq 1) 'Exact original value restored'
    Restore-BnqqJournal $script:currentJournal.File|Out-Null
    Check ($script:state.Value -eq 1) 'Idempotent recovery'
    $absent=[pscustomobject]@{Path=$script:state.Path;Name=$script:state.Name;KeyExisted=$false;Existed=$false;Kind=$null;Value=$null}
    $script:state=$absent|Select-Object *
    $j=New-BnqqJournal 'new-leaf';$before=$script:state|Select-Object *
    $after=[pscustomobject]@{Path=$before.Path;Name=$before.Name;KeyExisted=$true;Existed=$true;Kind='DWord';Value=0}
    Invoke-BnqqJournalOperation $j ([pscustomobject]@{Kind='Registry';Before=$before;After=$after})
    Restore-BnqqJournal $j.File|Out-Null
    Check (Test-BnqqSameValue $script:state $absent) 'Previously absent key/value restored as absent'
    $script:state=[pscustomobject]@{Path=$before.Path;Name=$before.Name;KeyExisted=$true;Existed=$true;Kind='DWord';Value=1}
    $j=New-BnqqJournal 'snapshot-race';$op=New-FixtureOperation;$script:state.Value=9
    Throws {Invoke-BnqqJournalOperation $j $op} 'Changed target refused before mutation'
    Check ($script:state.Value -eq 9 -and $j.Data.Entries.Count -eq 0) 'No stale snapshot overwrite'
    Restore-BnqqJournal $j.File|Out-Null;$script:state.Value=1
    $script:currentJournal=New-BnqqJournal 'partial';$script:assertPrepared=$true;$script:failAfterWrite=$true
    Throws {Invoke-BnqqJournalOperation $script:currentJournal (New-FixtureOperation)} 'Mutation failure propagated'
    Check ((Get-Content $script:currentJournal.File -Raw|ConvertFrom-Json).Status -eq 'NeedsRecovery') 'Failure journal retained'
    $script:assertPrepared=$false
    Restore-BnqqJournal $script:currentJournal.File|Out-Null
    Check ($script:state.Value -eq 1) 'Partial failure restored'
    $j=New-BnqqJournal 'conflict';Invoke-BnqqJournalOperation $j (New-FixtureOperation)
    $script:state.Value=9
    Throws {Restore-BnqqJournal $j.File} 'External conflict blocks rollback'
    Check ($script:state.Value -eq 9) 'External value preserved'
    $script:state.Value=0;Restore-BnqqJournal $j.File|Out-Null
    $bad=New-FixtureOperation;$bad.Before.Path='HKLM:\SOFTWARE\Untrusted'
    Throws {Assert-BnqqOperation $bad} 'Unapproved journal target refused'
    $bad=[pscustomobject]@{Kind='Shell';Before=@{};After=@{}}
    Throws {Assert-BnqqOperation $bad} 'No arbitrary journal command execution'
    $j=New-BnqqJournal 'owner';$j.Data.Owner='wrong';Write-BnqqAtomicJson $j.Data $j.File
    Throws {Restore-BnqqJournal $j.File} 'Cross-owner journal refused'
    Remove-Item -LiteralPath $j.File

    $script:probe=[pscustomobject]@{Events=@([pscustomobject]@{Id=18});Error=$null}
    function Get-BnqqWheaEvents {param($Since);return $script:probe}
    Throws {Assert-BnqqWheaBaseline} 'Recent WHEA blocks changes'
    $script:probe=[pscustomobject]@{Events=@();Error='access denied'}
    Throws {Assert-BnqqWheaBaseline} 'Unavailable WHEA telemetry fails closed'
    $script:probe=[pscustomobject]@{Events=@();Error=$null}
    function Get-BnqqConfigurationFingerprint {return $script:fingerprint}
    $script:fingerprint='same-boot-and-config'
    Throws {Assert-BnqqHeavyQa} 'Missing HeavyQA refused'
    $cert=[pscustomobject]@{Schema=2;Owner=(Get-BnqqOwner);Generated=[datetime]::UtcNow.ToString('o');Verdict='PASS';CpuVerified=$true;IoVerified=$true;Completed=$true;Seconds=600;IdleTailSeconds=30;WheaCount=0;Fingerprint=$script:fingerprint}
    $certPath=Join-Path $script:BnqqDataRoot 'heavyqa.json';Write-BnqqAtomicJson $cert $certPath
    Check (Get-BnqqLatestHeavyQa).Passed 'Recent matching verified QA accepted'
    $script:fingerprint='changed-boot'
    Check (-not (Get-BnqqLatestHeavyQa).Passed) 'Boot/config drift invalidates QA'
    $script:fingerprint=$cert.Fingerprint;$cert.Generated=[datetime]::UtcNow.AddHours(1).ToString('o');Write-BnqqAtomicJson $cert $certPath
    Check (-not (Get-BnqqLatestHeavyQa).Passed) 'Future certificate refused'
    $cert.Generated=[datetime]::UtcNow.AddHours(-25).ToString('o');Write-BnqqAtomicJson $cert $certPath
    Check (-not (Get-BnqqLatestHeavyQa).Passed) 'Expired QA refused'
    $cert.Generated=[datetime]::UtcNow.ToString('o');$cert.IoVerified=$false;Write-BnqqAtomicJson $cert $certPath
    Check (-not (Get-BnqqLatestHeavyQa).Passed) 'Unverified IO cannot pass'
    function Test-BnqqAdmin {return $true}
    function Assert-BnqqRecordingCapability {}
    Throws {Invoke-BnqqApply -Profile recording-off} 'Apply blocked without full QA'
    Check ($script:state.Value -eq 1) 'Blocked apply left state unchanged'
    Invoke-BnqqApply -Profile latency | Out-Null
    Check ($script:state.Value -eq 1) 'Latency default is diagnostics only'

    # Partial state must be a subset of the planned transition, not an arbitrary external value.
    $powerBefore=[pscustomobject]@{Scheme='11111111-1111-1111-1111-111111111111';Sub='SUB_PROCESSOR';Setting='IDLEDISABLE';AC=0;DC=0}
    $powerAfter=$powerBefore|Select-Object *;$powerAfter.AC=1
    $powerOp=[pscustomobject]@{Kind='Power';Before=$powerBefore;After=$powerAfter}
    Check (Test-BnqqPartialState $powerOp $powerAfter) 'Admitted partial power transition recognized'
    $external=$powerAfter|Select-Object *;$external.DC=7
    Check (-not (Test-BnqqPartialState $powerOp $external)) 'Unexpected partial power transition rejected'
    $stale=[pscustomobject]@{Kind='Process';Before=[pscustomobject]@{ProcessId=$PID;Name='cs2';StartTime='1900-01-01T00:00:00.0000000Z';Priority='Normal';Affinity='1'}}
    $stale|Add-Member After ($stale.Before|Select-Object *)
    Check ($null -eq (Get-BnqqOperationState $stale)) 'Reused PID identity never targets current process'
    $j=New-BnqqJournal 'pid-reuse';$stale|Add-Member Status Prepared;$j.Data.Entries=@($stale);Write-BnqqAtomicJson $j.Data $j.File
    Check ((Restore-BnqqJournal $j.File).Entries[0].Status -eq 'Exited') 'Recovery skips reused PID'
    $original='--profile-directory="Profile 1" --disable-background-timer-throttling --custom="x y" --disable-renderer-backgrounding'
    $clean=Remove-BnqqBadFlags $original
    Check ($clean -eq '--profile-directory="Profile 1"  --custom="x y" ') 'Only exact legacy tokens removed; remaining bytes retained'
    Check ((Remove-BnqqBadFlags '--disable-renderer-backgrounding-extra') -eq '--disable-renderer-backgrounding-extra') 'Similar unrelated flags retained'
    # Shortcut adapter mocked; COM and real user shortcuts are never touched.
    function Assert-BnqqShortcutPath {param($Path);if($Path -ne 'fixture.lnk'){throw 'Path not admitted'}}
    $script:shortcut=[pscustomobject]@{Path='fixture.lnk';Target='chrome.exe';Arguments=$original}
    function Get-BnqqShortcutSnapshot {param($Path);return ($script:shortcut|Select-Object *)}
    function Set-BnqqShortcutSnapshot {param($Snapshot);$script:shortcut=$Snapshot|Select-Object *}
    $before=$script:shortcut|Select-Object *;$after=$before|Select-Object *;$after.Arguments=$clean
    $j=New-BnqqJournal 'shortcut';$op=[pscustomobject]@{Kind='Shortcut';Before=$before;After=$after}
    Invoke-BnqqJournalOperation $j $op
    Check ($script:shortcut.Arguments -ceq $clean) 'Journalled shortcut repair'
    Restore-BnqqJournal $j.File|Out-Null
    Check ($script:shortcut.Arguments -ceq $original) 'Exact shortcut argument rollback'

    $csv=Join-Path $script:BnqqDataRoot 'frames.csv'
    $lines=@('Application,ProcessID,SwapChainAddress,PresentRuntime,PresentMode,TimeInMs,MsBetweenPresents')
    for($i=0;$i -lt 1000;$i++){$ms=if($i -eq 999){100}else{10};$lines+=('cs2.exe,1,0x1,DXGI,Hardware: Independent Flip,{0},{1}' -f ($i*10),$ms)}
    $lines|Set-Content $csv -Encoding UTF8
    $stats=Get-BnqqFrameStats $csv -MinimumSeconds 0
    Check ($stats.Frames -eq 1000) 'Frames counted'
    Check ($stats.P99Ms -eq 10 -and $stats.MaxMs -eq 100) 'Nearest rank p99 distinct from max'
    Check ([math]::Abs($stats.JitterMs-2.8446265) -lt .001) 'Population jitter verified'
    Check ($stats.Low01Fps -eq 10) 'Slowest 0.1 percent reciprocal mean'
    Check ($stats.DurationSeconds -eq 9.99) 'Duration uses timestamps'
    Throws {Get-BnqqFrameStats $csv -MinimumSeconds 20} 'Short capture refused'
    Add-Content $csv 'cs2.exe,1,0x2,DXGI,Hardware: Independent Flip,10000,10'
    Throws {Get-BnqqFrameStats $csv -MinimumSeconds 0} 'Mixed swapchains rejected'
    $filtered=Get-BnqqFrameStats $csv -SwapChain 0x1 -MinimumSeconds 0
    Check ($filtered.Frames -eq 1000) 'Explicit stream filter works'
    $badCsv=Join-Path $script:BnqqDataRoot 'nan.csv'
    @('ProcessID,SwapChainAddress,TimeInMs,MsBetweenPresents','1,0x1,0,NaN','1,0x1,10,Infinity')|Set-Content $badCsv
    Throws {Get-BnqqFrameStats $badCsv -MinimumSeconds 0} 'NaN/Infinity cannot poison metrics'
    @('ProcessID,SwapChainAddress,CPUStartTime,FrameTime','1,0x1,0,10','1,0x1,10,10')|Set-Content $badCsv
    Check ((Get-BnqqFrameStats $badCsv -MinimumSeconds 0).Metric -eq 'FrameTime') 'Alternative schema explicit'

    $files=@();$start=[datetime]::UtcNow
    for($i=0;$i -lt 6;$i++){
        $variant=if($i%2 -eq 0){'baseline'}else{'candidate'}
        $p99=if($variant -eq 'baseline'){10+$i*.01}else{8+$i*.01}
        $run=[pscustomobject]@{Schema=2;Started=$start.AddMinutes($i).ToString('o');Context=[pscustomobject]@{ExperimentId='fixture';Scenario='same';SettingsHash='same'};Variant=$variant;PresentMonHash='same';Stats=[pscustomobject]@{Schema=2;Metric='MsBetweenPresents';Runtime='DXGI';SkipSeconds=5;DurationSeconds=60;Frames=10000;AvgFps=200;Low1Fps=100;Low01Fps=80;P99Ms=$p99;P999Ms=20;JitterMs=1;StuttersPerMinute=1}}
        $path=Join-Path $script:BnqqDataRoot ('run'+$i+'.json');Write-BnqqAtomicJson $run $path;$files+=$path
    }
    Check ((Compare-BnqqFrameBench $files).Effective -eq $true) 'Controlled separated p99 accepted with limited claim'
    Throws {Compare-BnqqFrameBench $files[0..3]} 'Comparison requires three plus three'
    $run=Get-Content $files[5] -Raw|ConvertFrom-Json;$run.Context.Scenario='different';Write-BnqqAtomicJson $run $files[5]
    Throws {Compare-BnqqFrameBench $files} 'Mismatched scenarios rejected'

    # Native read-only topology check, then unsupported layout fixtures.
    $cores=@(Get-BnqqTopology)
    Check ($cores.Count -gt 0) 'Native topology available'
    if($cores.Count -ge 4 -and @($cores|Where-Object Group -ne 0).Count -eq 0 -and @($cores|Select-Object -ExpandProperty EfficiencyClass -Unique).Count -eq 1){
        Check ((Get-BnqqSafeGameMask) -gt 0) 'Measured physical-core experiment mask'
    }else{Throws {Get-BnqqSafeGameMask} 'Unsupported/small topology rejected'}
    function Get-BnqqTopology {return @([pscustomobject]@{Group=1;Mask=3;EfficiencyClass=0})}
    Throws {Get-BnqqSafeGameMask} 'Multi-group mask fails closed'

    # Compile the actual observer; enqueue concurrently without subscribing to WMI.
    $observerSource=Get-Content (Join-Path $script:BnqqRoot 'lib\BnqqProcessLasso.cs') -Raw
    $observerSource+=@'

public static class QueueStress {
    public static void Run(){System.Threading.Tasks.Parallel.For(1,2001,delegate(int i){BnqqProcessLasso.TestEnqueue(i);});}
}
'@
    Add-Type -TypeDefinition $observerSource -ReferencedAssemblies System.Management -ErrorAction Stop
    [QueueStress]::Run();$counts=[BnqqProcessLasso]::Counters()
    Check ($counts[0] -le 64 -and $counts[1] -le 512) 'Concurrent churn stays within hard limits'
    Check ($counts[0]+$counts[3] -eq 2000) 'Every queued/dropped event accounted'
    [void][BnqqProcessLasso]::Drain()
    Check ([BnqqProcessLasso]::Counters()[0] -eq 0) 'Queue drains without negative counters'
    [BnqqProcessLasso]::Stop()

    function Get-CimInstance {param($ClassName);throw 'Injected WMI failure'}
    $unknown=Get-BnqqHardware
    Check ($unknown.Errors.Count -eq 7) 'Every failed telemetry source reported'
    Check (-not $unknown.CpuMatchesDeclared -and $unknown.BoardConfidence -like 'Unverified*') 'Declared hardware never impersonates measured hardware'

    # Short worker self-test: own threads and a temporary file only; no long machine stress.
    Add-Type -Path (Join-Path $script:BnqqRoot 'lib\StabilityLoad.cs') -ErrorAction Stop
    $load=New-Object Bnqq.VerifiedLoad;$io=Join-Path $script:BnqqDataRoot 'worker.bin'
    try{$load.Start(1,$io);Start-Sleep -Milliseconds 500;$load.Stop();Check (-not $load.Failed -and $load.CpuPasses -gt 0 -and $load.IoPasses -gt 0) 'CPU digest and IO readback self-test'}finally{$load.Dispose()}
    $load=New-Object Bnqq.VerifiedLoad
    try{$load.Start(1,$io);Start-Sleep -Milliseconds 150;$load.Stop();Check $load.Failed 'IO failure propagates from worker instead of passing'}finally{$load.Dispose()}

    # HeavyQA orchestration under virtual time and deterministic workers. No 10-minute stress.
    $script:clock=[datetime]::UtcNow;$script:phase='idle';$script:qaMode='pass';$script:stopped=$false
    function Get-BnqqQaPowerEvents {param($Since);return @()}
    function Get-BnqqQaNow {$script:clock=$script:clock.AddSeconds(15);return $script:clock}
    function Start-Sleep {param($Seconds,$Milliseconds)}
    function New-BnqqVerifiedLoad {
        $fake=[pscustomobject]@{CpuPasses=100;IoPasses=100;Failed=$false;Running=$true}
        $fake|Add-Member ScriptMethod Start {param($Threads,$File);$script:phase='load'}
        $fake|Add-Member ScriptMethod Stop {$script:phase='tail';$script:stopped=$true}
        $fake|Add-Member ScriptMethod Dispose {$script:phase='cleanup'}
        return $fake
    }
    function Get-BnqqWheaEvents {
        param($Since)
        $fail=($script:qaMode -eq 'load-error' -and $script:phase -eq 'load') -or ($script:qaMode -eq 'tail-error' -and $script:phase -eq 'tail')
        return [pscustomobject]@{Events=$(if($fail){@([pscustomobject]@{Id=18})}else{@()});Error=$null}
    }
    $result=Test-BnqqHeavyQA -Minutes 10
    Check ($result.Verdict -eq 'PASS' -and $result.Completed -and $script:stopped) 'HeavyQA complete mixed load and idle orchestration'
    $script:qaMode='load-error';$script:phase='idle'
    $result=Test-BnqqHeavyQA -Minutes 10
    Check ($result.Verdict -eq 'FAIL' -and $result.WheaCount -eq 1) 'HeavyQA aborts on WHEA during load'
    $script:qaMode='tail-error';$script:phase='idle'
    $result=Test-BnqqHeavyQA -Minutes 10
    Check ($result.Verdict -eq 'FAIL' -and $result.WheaCount -eq 1) 'HeavyQA rejects WHEA during idle tail'
    Check ((Get-Content $certPath -Raw|ConvertFrom-Json).Verdict -eq 'FAIL') 'Failed QA replaces previous PASS'
    Write-Host ('PASS: '+$script:checks+' checks; no machine tuning applied.') -ForegroundColor Green
}finally{
    $resolved=[IO.Path]::GetFullPath($script:BnqqDataRoot)
    if($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'bnqq-tests-*'){
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
