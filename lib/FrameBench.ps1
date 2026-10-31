function Get-BnqqPresentMonPath {
    $cmd=Get-Command presentmon.exe -ErrorAction SilentlyContinue
    if($cmd){return $cmd.Source}
    foreach($dir in @((Join-Path $env:ProgramFiles 'Intel\PresentMon'),(Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'))){
        if(Test-Path $dir){$f=Get-ChildItem $dir -Recurse -Filter 'PresentMon*.exe' -File -ErrorAction SilentlyContinue | Where-Object {$_.Name -notmatch 'service|overlay'} | Select-Object -First 1;if($f){return $f.FullName}}
    }
    throw 'PresentMon console nao encontrado. Informe -PresentMonPath; sem download automatico.'
}
function Convert-BnqqFiniteNumber {
    param($Text)
    $v=[double]0
    if(-not [double]::TryParse([string]$Text,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$v) -or [double]::IsNaN($v) -or [double]::IsInfinity($v)){throw 'Numero nao finito ou ausente'}
    return $v
}
function Get-BnqqPercentile {
    param([double[]]$Sorted,[double]$P)
    # Nearest-rank, not reciprocal of average slowest 1%.
    return $Sorted[[math]::Max(0,[math]::Ceiling($P*$Sorted.Length)-1)]
}
function Get-BnqqFrameStats {
    param([Parameter(Mandatory)][string]$CsvPath,[ValidateRange(0,30)][int]$SkipSeconds=0,[int]$ProcessId=0,[string]$SwapChain='',[ValidateRange(0,300)][double]$MinimumSeconds=10)
    $rows=@(Import-Csv -LiteralPath $CsvPath -ErrorAction Stop)
    if(-not $rows.Count){throw 'CSV vazio'}
    $headers=@($rows[0].PSObject.Properties.Name)
    $durationColumn=if($headers -contains 'MsBetweenPresents'){'MsBetweenPresents'}elseif($headers -contains 'FrameTime'){'FrameTime'}else{throw 'Schema desconhecido: faltam MsBetweenPresents/FrameTime'}
    $timeColumn=@('TimeInMs','CPUStartTimeInMs','CPUStartTime')|Where-Object {$headers -contains $_}|Select-Object -First 1
    if(-not $timeColumn -or $headers -notcontains 'ProcessID' -or $headers -notcontains 'SwapChainAddress'){throw 'Schema sem timestamp/PID/swap chain'}
    if($ProcessId){$rows=@($rows|Where-Object {[string]$_.ProcessID -eq [string]$ProcessId})}
    if($SwapChain){$rows=@($rows|Where-Object {$_.SwapChainAddress -eq $SwapChain})}
    if(-not $rows.Count){throw 'Nenhum frame para filtro selecionado'}
    $streams=@($rows|Group-Object ProcessID,SwapChainAddress,PresentRuntime)
    if($streams.Count -ne 1){throw ('Multiplos streams: selecione PID e SwapChain; fontes encontradas: '+(($streams|ForEach-Object {$_.Name+' ('+$_.Count+')'}) -join '; '))}
    $valid=New-Object 'Collections.Generic.List[object]';$rejected=0
    foreach($r in $rows){
        try{
            $ms=Convert-BnqqFiniteNumber $r.$durationColumn
            $time=Convert-BnqqFiniteNumber $r.$timeColumn
            if($ms -le 0 -or $time -lt 0){throw 'Intervalo invalido'}
            $valid.Add([pscustomobject]@{Time=$time;Ms=$ms})
        }catch{$rejected++}
    }
    if($valid.Count -lt 2 -or $rejected -gt [math]::Max(1,$rows.Count*.01)){throw 'Amostra invalida ou mais de 1% de linhas rejeitadas'}
    $first=($valid|Measure-Object Time -Minimum).Minimum
    $valid=@($valid|Where-Object {$_.Time -ge $first+1000*$SkipSeconds}|Sort-Object Time)
    if($valid.Count -lt 2){throw 'Amostra insuficiente apos warmup'}
    for($i=1;$i -lt $valid.Count;$i++){if($valid[$i].Time -le $valid[$i-1].Time){throw 'Timestamps duplicados/sem progressao no mesmo stream'}}
    $duration=($valid[-1].Time-$valid[0].Time)/1000
    if($duration -lt $MinimumSeconds){throw 'Captura curta demais para comparacao'}
    $times=[double[]]@($valid|ForEach-Object {$_.Ms});[Array]::Sort($times)
    $avg=($times|Measure-Object -Average).Average
    $slow=$times.Clone();[Array]::Reverse($slow)
    $low1=($slow[0..([math]::Ceiling($times.Length*.01)-1)]|Measure-Object -Average).Average
    $low01=($slow[0..([math]::Ceiling($times.Length*.001)-1)]|Measure-Object -Average).Average
    $variance=($times|ForEach-Object {($_-$avg)*($_-$avg)}|Measure-Object -Sum).Sum/$times.Length
    $stutters=@($times|Where-Object {$_ -gt 16.667}).Count
    return [pscustomobject]@{
        Schema=2;Csv=[IO.Path]::GetFullPath($CsvPath);Metric=$durationColumn;TimeColumn=$timeColumn
        ProcessId=$rows[0].ProcessID;SwapChain=$rows[0].SwapChainAddress;Runtime=$rows[0].PresentRuntime
        PresentModes=@($rows|Select-Object -ExpandProperty PresentMode -Unique -ErrorAction SilentlyContinue)
        Frames=$times.Length;RejectedRows=$rejected;SkipSeconds=$SkipSeconds;DurationSeconds=[math]::Round($duration,4)
        AvgFps=[math]::Round(1000/$avg,3);AvgMs=$avg;Low1Fps=[math]::Round(1000/$low1,3);Low01Fps=[math]::Round(1000/$low01,3)
        JitterMs=[math]::Sqrt($variance);P95Ms=(Get-BnqqPercentile $times .95);P99Ms=(Get-BnqqPercentile $times .99);P999Ms=(Get-BnqqPercentile $times .999)
        MinMs=$times[0];MaxMs=$times[-1];Over16Ms=$stutters;Over33Ms=@($times|Where-Object {$_ -gt 33.333}).Count
        StuttersPerMinute=60*$stutters/$duration;StutterDefinition='Interval >16.667 ms; fixed reporting threshold, not a universal perceptual threshold'
        Claim='Frame/present interval; not end-to-end input latency or a tweak effectiveness verdict'
    }
}
function Invoke-BnqqFrameBench {
    param([ValidateRange(10,300)][int]$Seconds=60,[string]$ProcessName='cs2.exe',[ValidateRange(0,30)][int]$SkipSeconds=5,[string]$Hotkey='',
        [Parameter(Mandatory)][string]$Scenario,[Parameter(Mandatory)][string]$SettingsHash,[Parameter(Mandatory)][string]$ExperimentId,
        [Parameter(Mandatory)][ValidateSet('baseline','candidate')][string]$Variant,[string]$SwapChain='',[string]$PresentMonPath,[switch]$GpuTelemetry)
    if($Seconds-$SkipSeconds -lt 10){throw 'Exigir pelo menos 10s uteis apos warmup'}
    if($GpuTelemetry -and $Hotkey){throw 'Telemetria GPU exige captura temporizada sem hotkey para preservar a janela de coleta'}
    if(-not $PresentMonPath){$PresentMonPath=Get-BnqqPresentMonPath}
    if(-not (Test-Path -LiteralPath $PresentMonPath -PathType Leaf)){throw 'PresentMon ausente'}
    if(Get-Command Assert-BnqqNoDynamicFocus -ErrorAction SilentlyContinue){Assert-BnqqNoDynamicFocus}
    $game=@(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($ProcessName)) -ErrorAction Stop)
    if($game.Count -ne 1){throw 'Selecione exatamente uma instancia do jogo'}
    $game=$game[0]
    try {
    $session=Join-Path (Get-BnqqDataRoot) ('captures\'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($session)
    $output=Join-Path $session 'frames.csv'
    $started=[datetime]::UtcNow.ToString('o')
    $machine=Get-BnqqHardware
    $context=[pscustomobject]@{ExperimentId=$ExperimentId;Scenario=$Scenario;SettingsHash=$SettingsHash;Game=$ProcessName;OS=@($machine.OS|Select-Object Version,BuildNumber);GPU=@($machine.GPU|Select-Object Name,DriverVersion,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate);CPU=@($machine.ObservedCPU|Select-Object Name,NumberOfCores,NumberOfLogicalProcessors)}
    if(-not @($context.OS).Count -or -not @($context.GPU).Count -or -not @($context.CPU).Count){throw 'Contexto de captura incompleto'}
    $arguments=@('--process_id',[string]$game.Id,'--output_file',$output,'--timed',[string]$Seconds,'--terminate_after_timed','--session_name',('BNQQ-'+[guid]::NewGuid().ToString('N')))
    if($Hotkey){$arguments+=@('--hotkey',$Hotkey)}
    Write-Host 'Capture o mesmo cenario aquecido. Nao use o watcher com intervencoes variaveis. CSV nao mede automaticamente mouse-tela.'
    $recorder=$null;$gpuData=$null
    try {
        if($GpuTelemetry){
            $recorder=Start-BnqqGpuRecorder $Seconds
            $context|Add-Member -NotePropertyName GpuInstrumentation -NotePropertyValue ([pscustomobject]@{Provider='NVAPI';IntervalMs=500;LibraryHash=$recorder.LibraryHash})
        }
        & $PresentMonPath @arguments | ForEach-Object {Write-Host ([string]$_)}
        if($LASTEXITCODE -ne 0){throw ('PresentMon falhou: '+$LASTEXITCODE)}
    }finally{if($recorder){$gpuData=Stop-BnqqGpuRecorder $recorder}}
    $files=@(Get-ChildItem -LiteralPath $session -Filter 'frames*.csv' -File)
    if($files.Count -ne 1){throw 'Esperada uma captura; use uma sessao/hotkey por rodada e inspecione os CSVs produzidos'}
    $stats=Get-BnqqFrameStats $files[0].FullName -SkipSeconds $SkipSeconds -ProcessId $game.Id -SwapChain $SwapChain
    $result=[pscustomobject]@{Schema=2;Started=$started;Context=$context;Variant=$Variant;PresentMonHash=(Get-FileHash $PresentMonPath).Hash;Process=(Get-BnqqProcessSnapshot $game.Id);Stats=$stats;Effective=$null;Verdict='UNCOMPARED'}
    if($GpuTelemetry){$result|Add-Member -NotePropertyName GpuTelemetry -NotePropertyValue $gpuData}
    $path=Join-Path $session 'result.json';Write-BnqqAtomicJson $result $path
    Write-Host ('Resultado: '+$path)
    return $result
    }finally{if($game -is [Diagnostics.Process]){$game.Dispose()}}
}
function Assert-BnqqGpuCaptureQuality {
    param($Capture)
    if(-not $Capture.Context.GpuInstrumentation){
        if($Capture.GpuTelemetry){throw 'Telemetria sem contrato de instrumentacao'}
        return
    }
    $mode=$Capture.Context.GpuInstrumentation;$t=$Capture.GpuTelemetry
    if($mode.Provider -cne 'NVAPI' -or $mode.IntervalMs -ne 500 -or $mode.LibraryHash -cnotmatch '^[A-F0-9]{64}$' -or $t.Schema -ne 1 -or $t.Provider -cne 'NVAPI' -or $t.LibraryHash -cne $mode.LibraryHash -or $t.IntervalMs -ne 500 -or $t.DeviceWide -isnot [bool] -or -not $t.DeviceWide -or $t.Status -cne 'Complete' -or $t.Error){throw 'Telemetria GPU incompleta/inconsistente'}
    $rows=@($t.Samples)
    if($rows.Count -lt 2 -or $rows.Count -gt 610){throw 'Amostras GPU fora dos limites'}
    $previous=-1.0;$first=0.0
    for($i=0;$i -lt $rows.Count;$i++){
        $r=$rows[$i];$seconds=Convert-BnqqFiniteNumber $r.Seconds
        $busy=Convert-BnqqFiniteNumber $r.GpuPercent;$temp=Convert-BnqqFiniteNumber $r.TemperatureC
        if($seconds -lt 0 -or $seconds -le $previous -or ($previous -ge 0 -and $seconds-$previous -gt 2) -or $busy -lt 0 -or $busy -gt 100 -or $temp -lt -50 -or $temp -gt 150){throw 'Serie temporal GPU invalida/lacunas excessivas'}
        foreach($key in @('GraphicsMHz','MemoryMHz')){if($null -ne $r.$key -and (Convert-BnqqFiniteNumber $r.$key) -lt 0){throw 'Clock GPU invalido'}}
        if($i -eq 0){$first=$seconds};$previous=$seconds
    }
    if(($previous-$first)+1 -lt 0.8*(Convert-BnqqFiniteNumber $Capture.Stats.DurationSeconds)){throw 'Cobertura temporal GPU insuficiente'}
}
function Compare-BnqqFrameBench {
    param([Parameter(Mandatory)][string[]]$Files)
    $runs=@($Files|ForEach-Object {Get-Content -LiteralPath $_ -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json}|Sort-Object Started)
    if(@($Files|Select-Object -Unique).Count -ne $Files.Count){throw 'Rodadas duplicadas'}
    $a=@($runs|Where-Object Variant -eq 'baseline');$b=@($runs|Where-Object Variant -eq 'candidate')
    if($a.Count -lt 3 -or $b.Count -lt 3){throw 'Exigir pelo menos 3 baselines e 3 candidatas intercaladas'}
    $ref=$runs[0]
    foreach($run in $runs){
        Assert-BnqqGpuCaptureQuality $run
        if($run.PSObject.Properties.Name -contains 'CaptureIntegrity' -and -not $run.CaptureIntegrity.Passed){throw 'Captura com guard reprovado; excluir da comparacao'}
        if($run.Variant -notin @('baseline','candidate') -or $run.Schema -ne 2 -or $run.Stats.Schema -ne 2 -or -not (Test-BnqqSameValue $run.Context $ref.Context) -or $run.PresentMonHash -cne $ref.PresentMonHash -or $run.Stats.Metric -ne $ref.Stats.Metric -or $run.Stats.Runtime -ne $ref.Stats.Runtime -or $run.Stats.SkipSeconds -ne $ref.Stats.SkipSeconds){throw 'Rodadas de contextos/ferramentas/metricas diferentes'}
        foreach($metric in @('AvgFps','Low1Fps','Low01Fps','P99Ms','P999Ms','JitterMs','StuttersPerMinute')){
            $v=Convert-BnqqFiniteNumber $run.Stats.$metric
            if($v -lt 0 -or ($metric -in @('AvgFps','Low1Fps','Low01Fps','P99Ms','P999Ms') -and $v -eq 0)){throw 'Metrica invalida'}
        }
        if($run.Stats.DurationSeconds -lt 10 -or $run.Stats.Frames -lt 1000){throw 'Amostra insuficiente'}
    }
    $transitions=0
    for($i=1;$i -lt $runs.Count;$i++){if($runs[$i].Variant -ne $runs[$i-1].Variant){$transitions++}}
    if($transitions -lt 3){throw 'Ordem agrupada: intercale A/B/BA para controlar drift'}
    $base=@($a|ForEach-Object {$_.Stats.P99Ms});$candidate=@($b|ForEach-Object {$_.Stats.P99Ms})
    $baseAvg=($base|Measure-Object -Average).Average;$candidateAvg=($candidate|Measure-Object -Average).Average
    $faster=($candidate|Measure-Object -Maximum).Maximum -lt ($base|Measure-Object -Minimum).Minimum
    $fpsOk=($b|ForEach-Object {$_.Stats.AvgFps}|Measure-Object -Average).Average -ge .99*($a|ForEach-Object {$_.Stats.AvgFps}|Measure-Object -Average).Average
    $tailOk=($b|ForEach-Object {$_.Stats.P999Ms}|Measure-Object -Average).Average -le ($a|ForEach-Object {$_.Stats.P999Ms}|Measure-Object -Average).Average
    $gates=[ordered]@{P99Separated=$faster;AverageFps=$fpsOk;P999=$tailOk}
    foreach($metric in @('Low1Fps','Low01Fps','JitterMs','StuttersPerMinute')){
        $av=($a|ForEach-Object {$_.Stats.$metric}|Measure-Object -Average).Average
        $bv=($b|ForEach-Object {$_.Stats.$metric}|Measure-Object -Average).Average
        $gates[$metric]=if($metric -in @('Low1Fps','Low01Fps')){$bv -ge .99*$av}else{$bv -le 1.01*$av}
    }
    $accepted=@($gates.Values|Where-Object {-not $_}).Count -eq 0
    return [pscustomobject]@{BaselineRuns=$a.Count;CandidateRuns=$b.Count;Gates=[pscustomobject]$gates;P99BaselineMs=$baseAvg;P99CandidateMs=$candidateAvg;P99DeltaPercent=100*($candidateAvg/$baseAvg-1);Effective=$(if($accepted){$true}else{$null});Verdict=$(if($accepted){'Vantagem de p99 nesta amostra controlada; repetir em outras sessoes'}else{'INCONCLUSIVE_OR_REGRESSION'});Limit='Sem teste de significancia formal; intervalo entre rodadas e contexto informado nao provam causalidade. Sem garantia universal ou de input lag.'}
}
