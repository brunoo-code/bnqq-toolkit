# Synthetic CPU/cache burst experiment; never presented as CS2 or a QA certificate.
function Get-BnqqSyntheticLogicalProcessors {return [Environment]::ProcessorCount}
function Get-BnqqSyntheticReference {
    param([string]$File)
    if(-not $File){return $null}
    $item=Get-Item -LiteralPath $File -ErrorAction Stop
    if($item.PSIsContainer -or $item.Length -gt 4MB){throw 'Referencia FrameBench invalida/grande demais'}
    $hash=(Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
    $r=Get-Content -LiteralPath $File -Raw -Encoding UTF8|ConvertFrom-Json
    if($r.Schema -ne 2 -or $r.Stats.Schema -ne 2 -or -not $r.Context.Scenario){throw 'Referencia exige resultado FrameBench schema 2'}
    $metrics=[ordered]@{}
    foreach($key in @('AvgFps','Low1Fps','Low01Fps','P99Ms','JitterMs')){
        $n=0.0
        if(-not [double]::TryParse([string]$r.Stats.$key,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$n) -or [double]::IsNaN($n) -or [double]::IsInfinity($n) -or $n -lt 0){throw 'Referencia com metrica invalida'}
        $metrics[$key]=$n
    }
    if((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -cne $hash){throw 'Referencia mudou durante a leitura'}
    [pscustomobject]@{FrameBenchSha256=$hash;Scenario=$r.Context.Scenario;Started=$r.Started;ObservedFrameMetrics=[pscustomobject]$metrics;Calibration='NotCalibrated: frame/present intervals do not specify CPU instructions, GPU shaders or memory access';UsedToSetLoadParameters=$false}
}
function Get-BnqqSyntheticPlan {
    param([ValidateRange(0,16)][int]$Threads=0,[ValidateRange(1,120)][int]$Seconds=30,[ValidateRange(10,90)][int]$DutyPercent=50,[ValidateRange(20,1000)][int]$CycleMs=100,[ValidateRange(1,16)][int]$MemoryMiB=4,[ValidateRange(0,30)][int]$IdleTailSeconds=10,[string]$ReferenceFile)
    $available=Get-BnqqSyntheticLogicalProcessors
    if($available -lt 1){throw 'Quantidade de CPUs desconhecida'}
    if($Threads -eq 0){$Threads=[math]::Min(4,$available)}
    if($Threads -gt $available){throw 'Synthetic nao admite mais workers que CPUs disponiveis'}
    [pscustomobject]@{Schema='BNQQ.SyntheticPlan.1';LogicalProcessors=$available;Threads=$Threads;Seconds=$Seconds;DutyPercent=$DutyPercent;CycleMs=$CycleMs;PerWorkerMemoryMiB=$MemoryMiB;TotalScratchMiB=$Threads*$MemoryMiB;IdleTailSeconds=$IdleTailSeconds;Reference=(Get-BnqqSyntheticReference $ReferenceFile);GpuWorkload=$false;DiskWorkload=$false;PrefireEquivalent=$false;Requires='No recent WHEA, readable event log, no active game/capture; WHEA/power polling while running';Claim='Synthetic verified memory reads in CPU bursts. Duty is wall-time budget, not guaranteed CPU utilization. No game FPS, input latency or stability certificate.'}
}
function New-BnqqSyntheticLoad {
    if(-not ('Bnqq.SyntheticLoad' -as [type])){Add-Type -Path (Join-Path $script:BnqqRoot 'lib\SyntheticLoad.cs') -ErrorAction Stop}
    return (New-Object Bnqq.SyntheticLoad)
}
function New-BnqqSyntheticClock {return [Diagnostics.Stopwatch]::StartNew()}
function Get-BnqqSyntheticHostSample {
    $p=[Diagnostics.Process]::GetCurrentProcess()
    try{[pscustomobject]@{CpuMs=$p.TotalProcessorTime.TotalMilliseconds;WorkingSetBytes=$p.WorkingSet64}}
    finally{$p.Dispose()}
}
function Assert-BnqqSyntheticNoGame {
    $processes=@(Get-Process -ErrorAction Stop)
    try{
        $blocked=@($processes|Where-Object {$_.ProcessName -in @('cs2','VALORANT-Win64-Shipping') -or $_.ProcessName -like 'PresentMon*'})
        if($blocked.Count){throw ('Synthetic recusado com jogo/PresentMon ativo: '+(($blocked|Select-Object -ExpandProperty ProcessName -Unique)-join ', '))}
    }finally{foreach($p in $processes){$p.Dispose()}}
    if(Get-Command Assert-BnqqNoDynamicFocus -ErrorAction SilentlyContinue){Assert-BnqqNoDynamicFocus}
}
function Invoke-BnqqSyntheticBench {
    param([ValidateSet('plan','run')][string]$Action='plan',[ValidateRange(0,16)][int]$Threads=0,[ValidateRange(1,120)][int]$Seconds=30,[ValidateRange(10,90)][int]$DutyPercent=50,[ValidateRange(20,1000)][int]$CycleMs=100,[ValidateRange(1,16)][int]$MemoryMiB=4,[ValidateRange(0,30)][int]$IdleTailSeconds=10,[string]$ReferenceFile)
    $plan=Get-BnqqSyntheticPlan $Threads $Seconds $DutyPercent $CycleMs $MemoryMiB $IdleTailSeconds $ReferenceFile
    if($Action -eq 'plan'){return $plan}
    # A load test must not bypass the processor error that stopped the real game.
    Assert-BnqqWheaBaseline
    Assert-BnqqSyntheticNoGame
    $lock=$null;$load=$null;$errorText=$null;$completed=$false;$samples=@();$result=$null;$file=$null
    try{
        $lock=Enter-BnqqStateLock;Assert-BnqqNoPendingJournal
        $started=Get-Date
        $file=Join-Path (Get-BnqqDataRoot) ('synthetic\'+[guid]::NewGuid().ToString('N')+'.json')
        Write-BnqqAtomicJson @{Schema='BNQQ.SyntheticResult.1';Verdict='RUNNING';Owner=(Get-BnqqOwner);Started=$started.ToUniversalTime().ToString('o');Plan=$plan;PrefireEquivalent=$false} $file
        $load=New-BnqqSyntheticLoad
        $initial=Get-BnqqSyntheticHostSample
        $load.Start($plan.Threads,$Seconds,$DutyPercent,$CycleMs,$MemoryMiB)
        $clock=New-BnqqSyntheticClock
        $last=$initial;$lastAt=$clock.Elapsed.TotalSeconds
        while($clock.Elapsed.TotalSeconds -lt $Seconds){
            Assert-BnqqPhaseHealth $started
            if($load.Failed){throw 'Worker synthetic detectou erro de verificacao'}
            if(-not $load.Running -and $load.ElapsedSeconds -lt $Seconds){throw 'Workers encerraram antes do prazo'}
            Start-Sleep -Milliseconds 1000
            $now=$clock.Elapsed.TotalSeconds;$hostSample=Get-BnqqSyntheticHostSample
            $elapsed=$now-$lastAt
            $cpuDelta=$hostSample.CpuMs-$last.CpuMs
            if($elapsed -le 0 -or $cpuDelta -lt 0){throw 'Contadores de medicao synthetic invalidos'}
            $samples+=@([pscustomobject]@{Seconds=$now;HostCpuMsDelta=$cpuDelta;WindowSeconds=$elapsed;HostCpuEquivalentCores=$cpuDelta/(1000*$elapsed);HostMachineCpuPercent=100*$cpuDelta/(1000*$elapsed*$plan.LogicalProcessors);WorkingSetBytes=$hostSample.WorkingSetBytes;VerifiedPasses=$load.Passes})
            $last=$hostSample;$lastAt=$now
        }
        $load.Stop()
        if($load.Failed -or $load.Running -or $load.Passes -lt 1){throw 'Synthetic incompleto, sem progresso verificado ou worker ainda ativo'}
        $idleStart=$clock.Elapsed.TotalSeconds
        while($clock.Elapsed.TotalSeconds-$idleStart -lt $IdleTailSeconds){Assert-BnqqPhaseHealth $started;Start-Sleep -Milliseconds 1000}
        Assert-BnqqPhaseHealth $started
        $completed=$true
    }catch{$errorText=$_.Exception.Message}
    finally{
        try{
            if($load){$load.Dispose();if($load.Running){$completed=$false;$errorText='Worker nao encerrou; nao declarar resultado valido'}}
            if($file){
                $result=[pscustomobject]@{Schema='BNQQ.SyntheticResult.1';Owner=(Get-BnqqOwner);Started=$started.ToUniversalTime().ToString('o');Generated=[datetime]::UtcNow.ToString('o');Plan=$plan;Completed=$completed;VerifiedPasses=$(if($load){$load.Passes}else{0});Samples=$samples;Error=$errorText;Verdict=$(if($completed -and -not $errorText){'COMPLETED_NO_DETECTED_ERROR'}else{'FAILED'});PrefireEquivalent=$false;HeavyQaCertificate=$false;Instrumentation='Host CPU includes PowerShell and event-log polling; scheduling/thermal telemetry incomplete';ResultFile=$file}
                Write-BnqqAtomicJson $result $file
            }
        }finally{if($lock){$lock.Dispose()}}
    }
    if($errorText){throw ('Synthetic interrompido: '+$errorText+'; resultado: '+$file)}
    return $result
}
