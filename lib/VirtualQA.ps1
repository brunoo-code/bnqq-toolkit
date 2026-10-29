function Get-BnqqVirtualEngine {
    param([switch]$Force)

    $source = Join-Path $script:BnqqRoot 'lib\VirtualInGameQA.cs'
    if (-not (Test-Path -LiteralPath $source)) { throw 'VirtualInGameQA.cs nao encontrado' }

    $dir = Join-Path $env:TEMP 'BNQQ_QA\virtual'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $exe = Join-Path $dir 'VirtualInGameQA.exe'

    $needsBuild = $Force -or -not (Test-Path -LiteralPath $exe)
    if (-not $needsBuild) {
        $needsBuild = (Get-Item -LiteralPath $source).LastWriteTimeUtc -gt (Get-Item -LiteralPath $exe).LastWriteTimeUtc
    }
    if ($needsBuild) {
        $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
        if (-not (Test-Path -LiteralPath $csc)) { throw 'csc.exe nao encontrado para compilar o motor virtual' }
        & $csc /nologo /target:exe /optimize+ /out:$exe $source 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe)) {
            throw 'Falha ao compilar VirtualInGameQA.cs'
        }
    }
    return $exe
}

function Invoke-BnqqVirtualQa {
    param(
        [ValidateRange(10, 180)][int]$Seconds = 30,
        [ValidateRange(32, 256)][int]$Ticks = 128,
        [int]$Threads = 0,
        [long]$Mask = 0x5555
    )

    if (Get-Process -Name 'cs2', 'VALORANT-Win64-Shipping' -ErrorAction SilentlyContinue) {
        Write-Bnqq 'Virtual QA cancelado: jogo real em execucao' 'WARN'
        return
    }

    $watcher = Get-ScheduledTask -TaskName 'BNQQ Game Watcher' -ErrorAction SilentlyContinue
    if (-not $watcher -or $watcher.State -ne 'Running') {
        Write-Bnqq 'Virtual QA exige o Game Watcher em execucao' 'WARN'
        return
    }

    $engine = $null
    $bin = $null
    $game = $null
    $background = $null
    $proc = $null
    $stdout = Join-Path $env:TEMP 'BNQQ_QA\virtualqa.out'
    $stderr = Join-Path $env:TEMP 'BNQQ_QA\virtualqa.err'

    try {
        $engine = Get-BnqqVirtualEngine
        $bin = New-BnqqFakeEngine
        $backgroundExe = Join-Path (Split-Path $bin.Game -Parent) 'chrome.exe'
        Copy-Item -LiteralPath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Destination $backgroundExe -Force

        $background = Start-Process -FilePath $backgroundExe -ArgumentList '-NoProfile', '-Command', ('Start-Sleep -Seconds {0}' -f ($Seconds + 20)) -PassThru -WindowStyle Hidden
        $game = Start-Process -FilePath $bin.Game -ArgumentList '-NoProfile', '-Command', ('Start-Sleep -Seconds {0}' -f ($Seconds + 15)) -PassThru -WindowStyle Hidden

        $deadline = (Get-Date).AddSeconds(12)
        do {
            Start-Sleep -Seconds 1
            $gameProc = Get-Process -Id $game.Id -ErrorAction SilentlyContinue
            $bgProc = Get-Process -Id $background.Id -ErrorAction SilentlyContinue
            $gameAffinity = if ($gameProc) { '0x{0:X}' -f [int64]$gameProc.ProcessorAffinity } else { 'encerrado' }
            $bgAffinity = if ($bgProc) { '0x{0:X}' -f [int64]$bgProc.ProcessorAffinity } else { 'encerrado' }
            if ($gameAffinity -eq '0x5555' -and $bgAffinity -eq '0xAAAA') { break }
        } while ((Get-Date) -lt $deadline)

        $arguments = @('--seconds', $Seconds, '--ticks', $Ticks, '--mask', ('0x{0:X}' -f $Mask))
        if ($Threads -gt 0) { $arguments += @('--threads', $Threads) }

        $proc = Start-Process -FilePath $engine -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        try { $proc.ProcessorAffinity = [IntPtr]$Mask; $engineAffinity = '0x{0:X}' -f $Mask } catch { $engineAffinity = 'indisponivel' }

        $proc.WaitForExit(($Seconds + 30) * 1000) | Out-Null
        $finished = $proc.HasExited
        if (-not $finished) {
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch { }
        }
        $exitCode = if ($finished) { $proc.ExitCode } else { -1 }

        $engineText = if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw -Encoding UTF8 } else { '' }
        $engineErr = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw -Encoding UTF8 } else { '' }
        $metrics = @{}
        foreach ($line in ($engineText -split "`r?`n")) {
            if ($line -match '^([^=]+)=(.*)$') { $metrics[$Matches[1]] = $Matches[2] }
        }

        $gameProc = Get-Process -Id $game.Id -ErrorAction SilentlyContinue
        $bgProc = Get-Process -Id $background.Id -ErrorAction SilentlyContinue
        $gameAffinity = if ($gameProc) { '0x{0:X}' -f [int64]$gameProc.ProcessorAffinity } else { 'encerrado' }
        $bgAffinity = if ($bgProc) { '0x{0:X}' -f [int64]$bgProc.ProcessorAffinity } else { 'encerrado' }
        $timer = Get-BnqqTimerResolution

        $log = Get-ChildItem -Path (Join-Path $script:BnqqRoot 'reports') -Filter 'bnqq-*.log' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $logText = if ($log) { Get-Content -LiteralPath $log.FullName -Encoding UTF8 -Raw } else { '' }
        $detected = [bool]($logText -match 'Jogo detectado \(cs2\)')

        $stable = $metrics['stable'] -eq 'true'
        $timerOk = $timer.CurrentMs -le 0.6
        $gameOk = $gameAffinity -eq '0x5555'
        $bgOk = $bgAffinity -eq '0xAAAA'
        $engineOk = $finished -and $stable -and $engineAffinity -eq ('0x{0:X}' -f $Mask)
        $verdict = if ($stable -and $timerOk -and $gameOk -and $bgOk -and $engineOk -and $detected) { 'ESTAVEL' } else { 'REVISAR' }

        Write-Host ''
        Write-Host '  VIRTUAL IN-GAME QA' -ForegroundColor Cyan
        Write-Host '    Motor            C# sintetico (sem jogo real)' -ForegroundColor Gray
        Write-Host ('    Duracao          {0}s · tick {1} Hz' -f $Seconds, $Ticks) -ForegroundColor Gray
        Write-Host ('    Threads          {0} · mask {1}' -f $metrics['threads'], $metrics['mask']) -ForegroundColor Gray
        Write-Host ('    Ticks            {0} ({1} Hz)' -f $metrics['ticks'], $metrics['tick_hz']) -ForegroundColor Gray
        Write-Host ('    Jitter           avg {0} us · max {1} us' -f $metrics['jitter_avg_us'], $metrics['jitter_max_us']) -ForegroundColor Gray
        Write-Host ('    Fisica / memoria {0} ops / {1} ops' -f $metrics['physics_ops'], $metrics['memory_ops']) -ForegroundColor Gray
        Write-Host ('    Rede             {0} pacotes loopback' -f $metrics['network_packets']) -ForegroundColor Gray
        Write-Host ('    Timer            {0:N3} ms  [{1}]' -f $timer.CurrentMs, $(if ($timerOk) { '0.5 ms OK' } else { 'PENDENTE' })) -ForegroundColor $(if ($timerOk) { 'Green' } else { 'Yellow' })
        Write-Host ('    Afinidade jogo   {0}  [{1}]' -f $gameAffinity, $(if ($gameOk) { '0x5555 OK' } else { 'PENDENTE' })) -ForegroundColor $(if ($gameOk) { 'Green' } else { 'Yellow' })
        Write-Host ('    Afinidade SMT    {0}  [{1}]' -f $bgAffinity, $(if ($bgOk) { '0xAAAA OK' } else { 'PENDENTE' })) -ForegroundColor $(if ($bgOk) { 'Green' } else { 'Yellow' })
        Write-Host ('    Motor afinidade  {0}  [{1}]' -f $engineAffinity, $(if ($engineOk) { 'OK' } else { 'REVISAR' })) -ForegroundColor $(if ($engineOk) { 'Green' } else { 'Yellow' })
        Write-Host ('    Watcher detectou {0}' -f $(if ($detected) { 'sim' } else { 'nao' })) -ForegroundColor $(if ($detected) { 'Green' } else { 'Red' })
        if ($engineErr) { Write-Host ('    Stderr           {0}' -f $engineErr.Trim()) -ForegroundColor Yellow }
        Write-Host ('    Veredito         {0}' -f $verdict) -ForegroundColor $(if ($verdict -eq 'ESTAVEL') { 'Green' } else { 'Yellow' })
        Write-Host ''
    }
    catch {
        Write-Bnqq ('Virtual QA falhou: {0}' -f $_.Exception.Message) 'ERR'
    }
    finally {
        foreach ($p in @($proc, $game, $background)) {
            if ($p) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
        }
        if ($bin) {
            Get-Process -Name 'cs2', 'chrome' -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -like '*BNQQ_QA*' } |
                Stop-Process -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $bin.Game, $bin.Load -Force -ErrorAction SilentlyContinue
        }
    }
}
