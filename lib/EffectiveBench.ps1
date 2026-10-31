function Read-BnqqBaseline {
    param([Parameter(Mandatory)][string]$File)
    $d=Get-Content -LiteralPath $File -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json
    if($d -is [array] -or $d.Schema -ne 2 -or $d.Variant -ne 'baseline' -or -not $d.Context.ExperimentId -or -not $d.Context.Scenario -or -not $d.Context.SettingsHash){throw 'Informe result.json de uma baseline schema 2; nao o stdout misturado'}
    foreach($name in @('AvgFps','Low1Fps','Low01Fps','P99Ms','JitterMs')){[void](Convert-BnqqFiniteNumber $d.Stats.$name)}
    return $d
}
function Assert-BnqqNoInterferingWatcher {
    # Enabled tasks could start midway through the capture. Require disabled or absent.
    try{$all=@(Get-ScheduledTask -TaskName 'BNQQ*' -ErrorAction Stop)}
    catch{if($_.FullyQualifiedErrorId -like 'CmdletizationQuery_NotFound*'){$all=@()}else{throw}}
    $tasks=@($all | Where-Object {$_.TaskName -in @('BNQQ Game Watcher','BNQQ Audio Isolation') -and $_.State -ne 'Disabled'})
    if($tasks.Count){throw 'Desabilite/migre as tarefas legadas BNQQ Game Watcher/Audio Isolation antes do ensaio. Nao matar processos suspensores a forca.'}
    $processes=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction Stop)
    $pattern='(?i)-File\s+"?[^"\r\n]*\\bnqq-(watch|audio)\.ps1(?:"|\s|$)|-File\s+"?[^"\r\n]*\\bnqq\.ps1"?\s+watch(?:\s|$)'
    if(@($processes|Where-Object {$_.ProcessId -ne $PID -and $_.CommandLine -match $pattern}).Count){throw 'Processo watcher/audio detectado; use saida cooperativa ou migracao antes da captura'}
}
function Get-BnqqFullTopologyMask {
    $mask=[uint64]0
    foreach($core in @(Get-BnqqTopology)){
        if($core.Group -ne 0 -or $core.Mask -gt [uint64][int64]::MaxValue){throw 'Topologia nao representavel por afinidade escalar; nao presumir mascara'}
        $mask=$mask -bor [uint64]$core.Mask
    }
    if($mask -eq 0){throw 'Topologia vazia'}
    return [int64]$mask
}
function Compare-BnqqFramePair {
    param($Baseline,$Candidate)
    Assert-BnqqGpuCaptureQuality $Baseline
    Assert-BnqqGpuCaptureQuality $Candidate
    if($Baseline.Schema -ne 2 -or $Candidate.Schema -ne 2 -or $Baseline.Variant -ne 'baseline' -or $Candidate.Variant -ne 'candidate'){throw 'Par baseline/candidate schema 2 exigido'}
    if($Candidate.PSObject.Properties.Name -contains 'CaptureIntegrity' -and -not $Candidate.CaptureIntegrity.Passed){throw 'Candidata invalidada pelo guard'}
    if(-not (Test-BnqqSameValue $Baseline.Context $Candidate.Context) -or $Baseline.PresentMonHash -cne $Candidate.PresentMonHash -or $Baseline.Stats.Metric -cne $Candidate.Stats.Metric -or $Baseline.Stats.Runtime -cne $Candidate.Stats.Runtime -or $Baseline.Stats.SkipSeconds -ne $Candidate.Stats.SkipSeconds){throw 'Par com contexto, ferramenta, metrica, runtime ou warmup diferente'}
    $metrics=@(foreach($name in @('AvgFps','Low1Fps','Low01Fps','P99Ms','P999Ms','JitterMs')){
        $a=Convert-BnqqFiniteNumber $Baseline.Stats.$name;$b=Convert-BnqqFiniteNumber $Candidate.Stats.$name
        if($a -lt 0 -or $b -lt 0 -or ($name -ne 'JitterMs' -and ($a -eq 0 -or $b -eq 0))){throw 'Metrica invalida'}
        [pscustomobject]@{Metric=$name;Baseline=$a;Candidate=$b;Delta=($b-$a);DeltaPercent=$(if($a -ne 0){100*($b/$a-1)}else{$null});Better=$(if($a -eq $b){'equal'}elseif(($name -like '*Fps' -and $b -gt $a) -or ($name -notlike '*Fps' -and $b -lt $a)){'candidate'}else{'baseline'})}
    })
    return [pscustomobject]@{Schema=2;ExperimentId=$Baseline.Context.ExperimentId;BaselineStarted=$Baseline.Started;CandidateStarted=$Candidate.Started;BaselineProcess=$Baseline.Process;CandidateProcess=$Candidate.Process;Metrics=$metrics;Effective=$null;Verdict='EXPLORATORY_ONE_PAIR';Limit='Uma baseline com estado legado versus uma candidata limpa. Mudanca conjunta de prioridade/afinidade e instrumentacao; nao isola um tweak. Exige novas rodadas A/B/BA para veredito.'}
}
function Start-BnqqCaptureGuard {
    param($Expected,[string]$Directory)
    $ready=Join-Path $Directory 'guard.ready.json';$stop=Join-Path $Directory 'guard.stop'
    $job=Start-Job -ArgumentList $script:BnqqRoot,$Expected,$ready,$stop -ScriptBlock {
        param($Root,$Expected,$Ready,$Stop)
        $ErrorActionPreference='Stop';$script:BnqqRoot=$Root;$checks=0;$failure=$null
        foreach($name in @('Core','RuntimeLatency','EffectiveBench')){. (Join-Path $Root ('lib\'+$name+'.ps1'))}
        try{
            do{
                Assert-BnqqNoInterferingWatcher
                $live=Get-BnqqProcessSnapshot $Expected.ProcessId
                if(-not (Test-BnqqSameValue $live $Expected)){throw 'Prioridade, afinidade ou identidade mudou durante a captura'}
                $checks++
                if($checks -eq 1){Write-BnqqAtomicJson @{Ready=$true} $Ready}
                if(Test-Path -LiteralPath $Stop){break}
                Start-Sleep -Seconds 2
            }while($true)
        }catch{$failure=$_.Exception.Message}
        [pscustomobject]@{Checks=$checks;Error=$failure;Passed=($checks -ge 2 -and -not $failure);SamplingSeconds=2;Limit='Amostragem nao prova ausencia de transicoes entre sondagens'}
    }
    $until=[datetime]::UtcNow.AddSeconds(20)
    while(-not (Test-Path $ready) -and $job.State -eq 'Running' -and [datetime]::UtcNow -lt $until){Start-Sleep -Milliseconds 100}
    if(-not (Test-Path $ready)){
        $errorResult=Receive-Job $job -ErrorAction SilentlyContinue
        Stop-Job $job -ErrorAction SilentlyContinue;Remove-Job $job -Force -ErrorAction SilentlyContinue
        throw ('Guard nao iniciou: '+($errorResult|ConvertTo-Json -Compress))
    }
    return [pscustomobject]@{Job=$job;Stop=$stop}
}
function Stop-BnqqCaptureGuard {
    param($Guard)
    Write-BnqqAtomicJson @{Stop=$true} $Guard.Stop
    $done=Wait-Job $Guard.Job -Timeout 10
    if(-not $done){throw 'Guard de captura nao confirmou encerramento'}
    $result=Receive-Job $Guard.Job -ErrorAction Stop
    Remove-Job $Guard.Job -ErrorAction Stop
    return $result
}
function Invoke-BnqqEffectiveBench {
    param([Parameter(Mandatory)][string]$BaselineFile,[switch]$PrepareCleanState,[switch]$DryRun,[ValidateRange(15,300)][int]$Seconds=60,[string]$SwapChain,[string]$PresentMonPath)
    $baseline=Read-BnqqBaseline $BaselineFile
    $baselineHash=(Get-FileHash $BaselineFile -Algorithm SHA256).Hash
    if($DryRun){return [pscustomobject]@{BaselineFile=[IO.Path]::GetFullPath($BaselineFile);Experiment=$baseline.Context;BaselineProcess=$baseline.Process;PlannedPriority='Normal';PlannedAffinity='Measured full group-0 mask';Preconditions='Recent HeavyQA; disabled/absent legacy tasks; no watcher processes; exact tool/context';Changes='Temporary game scheduling only; no Windows profile reset';Effective=$null}}
    if(-not $PrepareCleanState){throw 'Use -PrepareCleanState explicitamente para o experimento temporario Normal/todos CPUs'}
    if(-not (Test-BnqqAdmin)){throw 'Execute em PowerShell administrativo apos revisar o codigo'}
    Assert-BnqqNoInterferingWatcher
    Assert-BnqqHeavyQa
    if(-not $PresentMonPath){$PresentMonPath=Get-BnqqPresentMonPath}
    if((Get-FileHash $PresentMonPath -Algorithm SHA256).Hash -cne $baseline.PresentMonHash){throw 'PresentMon difere da referencia; nao iniciar ensaio'}
    $game=@(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($baseline.Context.Game)) -ErrorAction Stop)
    if($game.Count -ne 1){throw 'Exigir uma instancia do jogo da referencia'}
    $before=Get-BnqqProcessSnapshot $game[0].Id;$after=$before|Select-Object *
    $after.Priority='Normal';$after.Affinity=(Get-BnqqFullTopologyMask).ToString()
    $lock=Enter-BnqqStateLock;$journal=$null;$guard=$null
    $session=Join-Path (Get-BnqqDataRoot) ('comparisons\'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($session)
    try{
        Assert-BnqqNoPendingJournal
        $journal=New-BnqqJournal 'effective-clean-process'
        Invoke-BnqqJournalOperation $journal ([pscustomobject]@{Kind='Process';Before=$before;After=$after})
        $guard=Start-BnqqCaptureGuard $after $session
        if(-not $SwapChain){$SwapChain=$baseline.Stats.SwapChain}
        $candidate=Invoke-BnqqFrameBench -Seconds $Seconds -ProcessName $baseline.Context.Game -SkipSeconds $baseline.Stats.SkipSeconds -Scenario $baseline.Context.Scenario -SettingsHash $baseline.Context.SettingsHash -ExperimentId $baseline.Context.ExperimentId -Variant candidate -SwapChain $SwapChain -PresentMonPath $PresentMonPath
        $integrity=Stop-BnqqCaptureGuard $guard;$guard=$null
        $candidate|Add-Member CaptureIntegrity $integrity
        $candidate|Add-Member Treatment 'Normal priority + measured full affinity; no persistent profile'
        $candidateFile=Join-Path (Split-Path $candidate.Stats.Csv -Parent) 'result.json'
        Write-BnqqAtomicJson $candidate $candidateFile
        if(-not $integrity.Passed){throw ('Captura candidata invalidada: '+$integrity.Error)}
        Assert-BnqqNoInterferingWatcher
        if(-not (Test-BnqqSameValue (Get-BnqqProcessSnapshot $game[0].Id) $after)){throw 'Estado final divergiu'}
        if((Get-FileHash $BaselineFile -Algorithm SHA256).Hash -cne $baselineHash){throw 'Referencia foi alterada durante o ensaio'}
        $comparison=Compare-BnqqFramePair $baseline $candidate
        $comparison|Add-Member BaselineFile ([IO.Path]::GetFullPath($BaselineFile))
        $comparison|Add-Member BaselineSha256 $baselineHash
        $comparison|Add-Member CandidateFile $candidateFile
        $comparison|Add-Member CaptureIntegrity $integrity
        Write-BnqqAtomicJson $comparison (Join-Path $session 'comparison.json')
        Write-Host ('Comparacao: '+(Join-Path $session 'comparison.json'))
        return $comparison
    }finally{
        try{if($guard){try{Stop-BnqqCaptureGuard $guard|Out-Null}catch{Stop-Job $guard.Job -ErrorAction SilentlyContinue;Remove-Job $guard.Job -Force -ErrorAction SilentlyContinue;Write-Warning $_}}}
        finally{try{if($journal){Restore-BnqqJournal $journal.File|Out-Null}}finally{$lock.Dispose()}}
    }
}
