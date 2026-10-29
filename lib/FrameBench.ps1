function Get-BnqqPresentMonPath {
    $cmd = Get-Command presentmon -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'),
        (Join-Path $env:ProgramFiles 'Intel\PresentMon'),
        (Join-Path ${env:ProgramFiles(x86)} 'Intel\PresentMon')
    )
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $found = Get-ChildItem -LiteralPath $root -Recurse -Filter 'presentmon.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

function Get-BnqqFrameStats {
    param([string]$CsvPath, [int]$SkipSeconds = 0)

    if (-not (Test-Path -LiteralPath $CsvPath)) { throw 'CSV de frametime nao encontrado' }
    $rows = @(Import-Csv -LiteralPath $CsvPath)
    $invariant = [Globalization.CultureInfo]::InvariantCulture
    $numberStyle = [Globalization.NumberStyles]::Float
    $frames = New-Object 'System.Collections.Generic.List[object]'
    foreach ($row in $rows) {
        $ms = 0.0
        if (-not [double]::TryParse([string]$row.MsBetweenPresents, $numberStyle, $invariant, [ref]$ms)) { continue }
        if ($ms -le 0) { continue }
        $time = 0.0
        [double]::TryParse([string]$row.TimeInMs, $numberStyle, $invariant, [ref]$time) | Out-Null
        $frames.Add([pscustomobject]@{ TimeMs = $time; Ms = $ms })
    }
    if ($frames.Count -eq 0) { throw 'CSV sem frames validos' }

    $skipMs = 0.0
    if ($SkipSeconds -gt 0) {
        $firstTime = ($frames | Measure-Object TimeMs -Minimum).Minimum
        $skipMs = $firstTime + ($SkipSeconds * 1000)
    }

    $times = New-Object 'System.Collections.Generic.List[double]'
    foreach ($frame in $frames) {
        if ($frame.TimeMs -lt $skipMs) { continue }
        $times.Add([double]$frame.Ms)
    }
    if ($times.Count -eq 0) { throw 'Nenhum frame apos o warmup' }

    $count = $times.Count
    $sorted = $times.ToArray()
    [Array]::Sort($sorted)
    [Array]::Reverse($sorted)
    $count1 = [math]::Max(1, [int][math]::Ceiling($count * 0.01))
    $count01 = [math]::Max(1, [int][math]::Ceiling($count * 0.001))
    $avgMs = ($times | Measure-Object -Average).Average
    $p1Ms = ($sorted[0..($count1 - 1)] | Measure-Object -Average).Average
    $p01Ms = ($sorted[0..($count01 - 1)] | Measure-Object -Average).Average
    $variance = (($times | ForEach-Object { ($_ - $avgMs) * ($_ - $avgMs) } | Measure-Object -Sum).Sum) / $count

    return [pscustomobject]@{
        Csv = $CsvPath
        Frames = $count
        DurationSeconds = [math]::Round((($times | Measure-Object -Sum).Sum / 1000), 2)
        AvgFps = [math]::Round(1000 / $avgMs, 2)
        AvgMs = [math]::Round($avgMs, 3)
        Low1Fps = [math]::Round(1000 / $p1Ms, 2)
        Low1Ms = [math]::Round($p1Ms, 3)
        Low01Fps = [math]::Round(1000 / $p01Ms, 2)
        Low01Ms = [math]::Round($p01Ms, 3)
        MaxMs = [math]::Round($sorted[0], 3)
        MinMs = [math]::Round($sorted[-1], 3)
        JitterMs = [math]::Round([math]::Sqrt($variance), 3)
    }
}

function Invoke-BnqqFrameBench {
    param(
        [ValidateRange(10, 300)][int]$Seconds = 60,
        [string]$ProcessName = 'cs2.exe',
        [ValidateRange(0, 30)][int]$SkipSeconds = 5,
        [string]$Hotkey = '',
        [string]$OutputFile
    )

    $pm = Get-BnqqPresentMonPath
    if (-not $pm) { throw 'PresentMon nao encontrado. Instale com: winget install Intel.PresentMon.Console' }
    if (-not (Test-BnqqAdmin)) { throw 'PresentMon exige elevacao' }

    $baseName = [IO.Path]::GetFileNameWithoutExtension($ProcessName)
    $game = @(Get-Process -Name $baseName -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($game.Count -eq 0) { throw ('Processo {0} nao esta aberto; abra o jogo antes do benchmark' -f $ProcessName) }
    $game = $game[0]
    $affinity = [int64]$game.ProcessorAffinity
    $priority = $game.PriorityClass
    Write-Bnqq ('FrameBench: {0} PID {1} | afinidade 0x{2:X} | prioridade {3}' -f $game.ProcessName, $game.Id, $affinity, $priority) 'INFO'
    if (Get-Command Get-BnqqSafeGameMask -ErrorAction SilentlyContinue) {
        $expectedMask = [int64](Get-BnqqSafeGameMask)
        if ($expectedMask -ne 0 -and $affinity -ne $expectedMask) {
            Write-Bnqq ('Afinidade fora do esperado 0x{0:X}; o watcher pode nao ter aplicado o plano' -f $expectedMask) 'WARN'
        }
    }
    if ($priority -ne [System.Diagnostics.ProcessPriorityClass]::AboveNormal) {
        Write-Bnqq ('Prioridade {0}; o padrao do watcher e AboveNormal' -f $priority) 'WARN'
    }

    if (-not $OutputFile) {
        $dir = Join-Path $script:BnqqRoot 'reports'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $OutputFile = Join-Path $dir ('framebench-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    if (Test-Path -LiteralPath $OutputFile) { Remove-Item -LiteralPath $OutputFile -Force -ErrorAction SilentlyContinue }

    $args = @(
        '--process_name', $ProcessName,
        '--output_file', $OutputFile,
        '--timed', $Seconds,
        '--terminate_after_timed',
        '--session_name', ('BNQQ-FrameBench-' + [guid]::NewGuid().ToString('N'))
    )
    if ($Hotkey) { $args += @('--hotkey', $Hotkey) }

    Write-Bnqq ('FrameBench: capturando {0}s de {1}' -f $Seconds, $ProcessName) 'STEP'
    if ($Hotkey) { Write-Bnqq ('Pressione {0} para iniciar a captura' -f $Hotkey) 'INFO' }
    & $pm @args 2>&1 | ForEach-Object { Write-Bnqq ([string]$_) 'INFO' }
    if ($LASTEXITCODE -ne 0) { throw ('PresentMon falhou: exit {0}' -f $LASTEXITCODE) }

    $stats = Get-BnqqFrameStats -CsvPath $OutputFile -SkipSeconds $SkipSeconds
    $jsonPath = [IO.Path]::ChangeExtension($OutputFile, '.json')
    $stats | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    Write-Host ''
    Write-Host '  FRAMEBENCH' -ForegroundColor Cyan
    Write-Host ('    CSV            {0}' -f $stats.Csv) -ForegroundColor Gray
    Write-Host ('    JSON           {0}' -f $jsonPath) -ForegroundColor Gray
    Write-Host ('    Frames         {0} em {1}s (skip {2}s)' -f $stats.Frames, $stats.DurationSeconds, $SkipSeconds) -ForegroundColor Gray
    Write-Host ('    FPS medio      {0}' -f $stats.AvgFps) -ForegroundColor Gray
    Write-Host ('    1% Low          {0} FPS  ({1} ms)' -f $stats.Low1Fps, $stats.Low1Ms) -ForegroundColor Yellow
    Write-Host ('    0.1% Low        {0} FPS  ({1} ms)' -f $stats.Low01Fps, $stats.Low01Ms) -ForegroundColor Yellow
    Write-Host ('    Frametime       avg {0} ms | max {1} ms | min {2} ms' -f $stats.AvgMs, $stats.MaxMs, $stats.MinMs) -ForegroundColor Gray
    Write-Host ('    Jitter          {0} ms (desvio padrao)' -f $stats.JitterMs) -ForegroundColor Gray
    Write-Host ''
    return $stats
}

