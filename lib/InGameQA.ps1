function Get-BnqqQaClock {
    $info = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
    if ($info -and $info.ActualFrequency -and [double]$info.ActualFrequency -gt 0) {
        return [math]::Round([double]$info.ActualFrequency, 0)
    }
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cpu) { return [int]$cpu.CurrentClockSpeed }
    return $null
}

function New-BnqqFakeEngine {
    $dir = Join-Path $env:TEMP 'BNQQ_QA'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    $loadExe = Join-Path $dir 'load.exe'
    $gameExe = Join-Path $dir 'cs2.exe'
    if (Test-Path -LiteralPath $loadExe) { Remove-Item -LiteralPath $loadExe -Force -ErrorAction SilentlyContinue }
    Copy-Item -LiteralPath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Destination $gameExe -Force

    $code = @'
using System;
using System.IO;
using System.Threading;

public static class Program {
    private static volatile bool stop;

    public static void Main(string[] args) {
        int seconds = 45;
        if (args.Length > 0) int.TryParse(args[0], out seconds);
        if (seconds < 5) seconds = 5;

        int n = Environment.ProcessorCount;
        Thread[] workers = new Thread[n];
        for (int i = 0; i < n; i++) {
            Thread t = new Thread(() => {
                uint state = (uint)(Thread.CurrentThread.ManagedThreadId * 2654435761u + 1);
                long sink = 0;
                while (!stop) {
                    for (int j = 0; j < 400000; j++) {
                        state ^= state << 13;
                        state ^= state >> 17;
                        state ^= state << 5;
                        sink += state;
                    }
                }
            });
            t.IsBackground = true;
            t.Priority = ThreadPriority.Highest;
            t.Start();
            workers[i] = t;
        }

        string ioDir = Path.Combine(Path.GetTempPath(), "BNQQ_QA_IO");
        Directory.CreateDirectory(ioDir);
        string ioFile = Path.Combine(ioDir, "stress.bin");
        Thread io = new Thread(() => {
            byte[] buffer = new byte[2 * 1024 * 1024];
            new Random(1).NextBytes(buffer);
            while (!stop) {
                try {
                    File.WriteAllBytes(ioFile, buffer);
                    using (FileStream fs = File.OpenRead(ioFile)) {
                        byte[] read = new byte[65536];
                        while (fs.Read(read, 0, read.Length) > 0 && !stop) { }
                    }
                } catch { }
            }
        });
        io.IsBackground = true;
        io.Start();

        Thread.Sleep(seconds * 1000);
        stop = true;
        foreach (Thread t in workers) { try { t.Join(2000); } catch { } }
        try { io.Join(2000); } catch { }
    }
}
'@

    Add-Type -TypeDefinition $code -OutputAssembly $loadExe -OutputType ConsoleApplication -ErrorAction Stop
    return [pscustomobject]@{ Game = $gameExe; Load = $loadExe }
}

function Invoke-BnqqInGameQa {
    param([ValidateRange(15, 180)][int]$Seconds = 45)

    if (Get-Process -Name 'cs2', 'VALORANT-Win64-Shipping' -ErrorAction SilentlyContinue) {
        Write-Bnqq 'QA cancelado: jogo real em execucao' 'WARN'
        return
    }

    $watcher = Get-ScheduledTask -TaskName 'BNQQ Game Watcher' -ErrorAction SilentlyContinue
    if (-not $watcher -or $watcher.State -ne 'Running') {
        Write-Bnqq 'QA exige o Game Watcher em execucao' 'WARN'
        return
    }

    $bin = $null
    $game = $null
    $load = $null
    $background = $null
    try {
        $bin = New-BnqqFakeEngine
        $backgroundExe = Join-Path (Split-Path $bin.Game -Parent) 'chrome.exe'
        Copy-Item -LiteralPath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Destination $backgroundExe -Force

        $background = Start-Process -FilePath $backgroundExe -ArgumentList '-NoProfile', '-Command', ('Start-Sleep -Seconds {0}' -f ($Seconds + 20)) -PassThru -WindowStyle Hidden
        $game = Start-Process -FilePath $bin.Game -ArgumentList '-NoProfile', '-Command', ('Start-Sleep -Seconds {0}' -f ($Seconds + 15)) -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 1
        $load = Start-Process -FilePath $bin.Load -ArgumentList ($Seconds + 10) -PassThru -WindowStyle Hidden

        Start-Sleep -Seconds 8
        $startClock = Get-BnqqQaClock
        $timer = Get-BnqqTimerResolution
        $gameProc = Get-Process -Id $game.Id -ErrorAction SilentlyContinue
        $bgProc = Get-Process -Id $background.Id -ErrorAction SilentlyContinue
        $loadProc = Get-Process -Id $load.Id -ErrorAction SilentlyContinue
        $gameAffinity = if ($gameProc) { '0x{0:X}' -f [int64]$gameProc.ProcessorAffinity } else { 'encerrado' }
        $bgAffinity = if ($bgProc) { '0x{0:X}' -f [int64]$bgProc.ProcessorAffinity } else { 'encerrado' }
        $loadAlive = [bool]$loadProc

        $log = Get-ChildItem -Path (Join-Path $script:BnqqRoot 'reports') -Filter 'bnqq-*.log' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $logText = if ($log) { Get-Content -LiteralPath $log.FullName -Encoding UTF8 -Raw } else { '' }
        $detected = [bool]($logText -match 'Jogo detectado \(cs2\)')
        $standby = if ((Get-BnqqFreeMemoryGB) -lt 4) { [bool]($logText -match 'Standby list purgada') } else { $false }

        Start-Sleep -Seconds ([math]::Max(8, $Seconds - 8))
        $endClock = Get-BnqqQaClock
        $temp = if (Get-Command Get-BnqqCpuTemperature -ErrorAction SilentlyContinue) { Get-BnqqCpuTemperature } else { $null }

        $throttle = if ($startClock -and $endClock) { [math]::Round((($startClock - $endClock) / $startClock) * 100, 1) } else { $null }
        $timerOk = $timer.CurrentMs -le 0.6
        $affinityOk = $gameAffinity -eq '0x5555'
        $bgOk = $bgAffinity -eq '0xAAAA'
        $tempText = if ($temp -and $temp.Celsius) { ('{0} C' -f $temp.Celsius) } else { 'indisponivel' }

        Write-Host ''
        Write-Host '  QA: STRESS TEST IN-GAME' -ForegroundColor Cyan
        Write-Host ('    Engine falso       cs2.exe + load.exe por {0}s' -f $Seconds) -ForegroundColor Gray
        Write-Host ('    Clock inicial      {0} MHz' -f $startClock) -ForegroundColor Gray
        Write-Host ('    Clock final        {0} MHz  (queda {1}%)' -f $endClock, $throttle) -ForegroundColor $(if ($throttle -and $throttle -gt 10) { 'Yellow' } else { 'Green' })
        Write-Host ('    Temperatura        {0}' -f $tempText) -ForegroundColor Gray
        Write-Host ('    Timer durante      {0:N3} ms  [{1}]' -f $timer.CurrentMs, $(if ($timerOk) { '0.5 ms OK' } else { 'PENDENTE' })) -ForegroundColor $(if ($timerOk) { 'Green' } else { 'Yellow' })
        Write-Host ('    Afinidade jogo     {0}  [{1}]' -f $gameAffinity, $(if ($affinityOk) { '0x5555 OK' } else { 'PENDENTE' })) -ForegroundColor $(if ($affinityOk) { 'Green' } else { 'Yellow' })
        Write-Host ('    Afinidade SMT      {0}  [{1}]' -f $bgAffinity, $(if ($bgOk) { '0xAAAA OK' } else { 'PENDENTE' })) -ForegroundColor $(if ($bgOk) { 'Green' } else { 'Yellow' })
        Write-Host ('    Carga C#           {0}' -f $(if ($loadAlive) { 'ativa' } else { 'encerrada' })) -ForegroundColor $(if ($loadAlive) { 'Green' } else { 'Yellow' })
        Write-Host ('    Watcher detectou   {0}' -f $(if ($detected) { 'sim' } else { 'nao' })) -ForegroundColor $(if ($detected) { 'Green' } else { 'Red' })
        Write-Host ('    Standby purge      {0}' -f $(if ($standby) { 'acionada' } else { 'nao necessaria (RAM >4GB)' })) -ForegroundColor Gray

        $verdict = if ($throttle -ne $null -and $throttle -le 10 -and $timerOk -and $detected -and $affinityOk) { 'ESTAVEL' } else { 'REVISAR' }
        Write-Host ('    Veredito           {0}' -f $verdict) -ForegroundColor $(if ($verdict -eq 'ESTAVEL') { 'Green' } else { 'Yellow' })
        Write-Host ''
    }
    catch {
        Write-Bnqq ('QA in-game falhou: {0}' -f $_.Exception.Message) 'ERR'
    }
    finally {
        foreach ($proc in @($game, $load, $background)) {
            if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
        }
        if ($bin) {
            Get-Process -Name 'cs2', 'chrome', 'load' -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -like '*BNQQ_QA*' } |
                Stop-Process -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $bin.Game, $bin.Load -Force -ErrorAction SilentlyContinue
        }
    }
}
