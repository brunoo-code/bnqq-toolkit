function Get-BnqqWheaEvents {
    param([datetime]$Since)

    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $Since } -ErrorAction Stop
    }
    catch {
        $message = $_.Exception.Message
        if ($message -match 'No events were found|Nenhum evento') {
            return [pscustomobject]@{ Events = @(); Error = $null }
        }
        return [pscustomobject]@{ Events = @(); Error = $message }
    }

    $whea = @($events | Where-Object {
        $_.ProviderName -match 'WHEA' -and ($_.Id -eq 18 -or $_.Id -eq 19)
    })

    return [pscustomobject]@{ Events = $whea; Error = $null }
}

if (-not ('Bnqq.StabilityLoad' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Threading;

namespace Bnqq {
    public static class StabilityLoad {
        private static volatile bool _stop;
        private static Thread[] _threads;
        private static long _sink;
        private static int _workers;

        public static bool IsRunning {
            get {
                if (_threads == null) return false;
                for (int i = 0; i < _threads.Length; i++) {
                    Thread t = _threads[i];
                    if (t != null && t.IsAlive) return true;
                }
                return false;
            }
        }

        public static int Workers { get { return _workers; } }

        public static void Start(int threads) {
            if (threads < 1) threads = Environment.ProcessorCount;
            _stop = false;
            _workers = threads;
            _threads = new Thread[threads];
            for (int i = 0; i < threads; i++) {
                Thread t = new Thread(Worker);
                t.IsBackground = true;
                t.Priority = ThreadPriority.Highest;
                t.Name = "BNQQ-Stability-" + i;
                _threads[i] = t;
                t.Start();
            }
        }

        public static void Stop() {
            _stop = true;
            Thread[] threads = _threads;
            if (threads == null) return;
            for (int i = 0; i < threads.Length; i++) {
                Thread t = threads[i];
                if (t != null) {
                    try { t.Join(2000); } catch { }
                }
            }
            _threads = null;
        }

        private static void Worker() {
            uint state = (uint)(Thread.CurrentThread.ManagedThreadId * 2654435761u + 1);
            long local = 0;
            while (!_stop) {
                for (int i = 0; i < 200000; i++) {
                    state ^= state << 13;
                    state ^= state >> 17;
                    state ^= state << 5;
                    local += state;
                }
                _sink = local;
            }
        }
    }
}
'@
}

function Test-BnqqStability {
    param(
        [ValidateRange(1, 30)]
        [int]$Minutes = 5,
        [ValidateRange(0, 3600)]
        [int]$Seconds = 0,
        [ValidateRange(0, 128)]
        [int]$Threads = 0,
        [string]$ReportDir
    )

    if ($Seconds -le 0) { $Seconds = $Minutes * 60 }
    if ($Threads -le 0) { $Threads = [Environment]::ProcessorCount }
    if ($Seconds -lt 10) { throw 'Duracao minima de 10 segundos para o teste WHEA.' }

    $start = Get-Date
    $deadline = $start.AddSeconds($Seconds)
    $whea = @()
    $wheaError = $null
    $aborted = $false

    Write-Bnqq ('Estabilidade PBO: {0}s em {1} threads (WHEA 18/19)...' -f $Seconds, $Threads) 'STEP'
    [Bnqq.StabilityLoad]::Start($Threads)

    try {
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
            $probe = Get-BnqqWheaEvents -Since $start
            if ($probe.Error) { $wheaError = $probe.Error; break }
            if (@($probe.Events).Count -gt 0) {
                $whea = @($probe.Events)
                $aborted = $true
                break
            }
        }

        if (-not $aborted -and -not $wheaError) {
            [Bnqq.StabilityLoad]::Stop()
            Start-Sleep -Seconds 5
            $probe = Get-BnqqWheaEvents -Since $start
            if ($probe.Error) { $wheaError = $probe.Error }
            elseif (@($probe.Events).Count -gt 0) {
                $whea = @($probe.Events)
                $aborted = $true
            }
        }
    }
    finally {
        [Bnqq.StabilityLoad]::Stop()
    }

    $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 0)
    $verdict = if ($aborted) { 'Instavel' } elseif ($wheaError) { 'Indeterminado' } else { 'Estavel' }

    Write-Host ''
    Write-Host ('  ESTABILIDADE PBO / WHEA ({0}s, {1} threads)' -f $Seconds, $Threads) -ForegroundColor Cyan
    Write-Host ('    Duracao real    {0}s' -f $elapsed) -ForegroundColor Gray

    if ($wheaError) {
        Write-Host ('    WHEA-Logger     erro de leitura: {0}' -f $wheaError) -ForegroundColor Yellow
        Write-Host '    Veredito         Indeterminado (Event Viewer inacessivel)' -ForegroundColor Yellow
        Write-Bnqq ('Estabilidade indeterminada: {0}' -f $wheaError) 'WARN'
    }
    elseif ($aborted) {
        Write-Host ('    WHEA-Logger     {0} evento(s) 18/19' -f @($whea).Count) -ForegroundColor Red
        foreach ($event in @($whea)) {
            Write-Host ('      {0}  Event {1}  {2}' -f $event.TimeCreated, $event.Id, $event.LevelDisplayName) -ForegroundColor Red
        }
        Write-Host '    Instabilidade detectada no Undervolt! Reduza o Curve Optimizer na BIOS (ex: de -15 para -10)' -ForegroundColor Red
        Write-Host '    Veredito         Instavel' -ForegroundColor Red
        Write-Bnqq 'Instabilidade detectada no Undervolt! Reduza o Curve Optimizer na BIOS (ex: de -15 para -10)' 'ERR'
    }
    else {
        Write-Host '    WHEA-Logger     nenhum Event 18/19' -ForegroundColor Green
        Write-Host '    Sistema 100% Estável no Curve Optimizer' -ForegroundColor Green
        Write-Host '    Veredito         Estavel' -ForegroundColor Green
        Write-Bnqq 'Sistema 100% Estável no Curve Optimizer' 'OK'
    }
    Write-Host ''

    if ($ReportDir) {
        if (-not (Test-Path -LiteralPath $ReportDir)) { New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null }
        $payload = [pscustomobject]@{
            Generated     = (Get-Date).ToString('o')
            Started       = $start.ToString('o')
            Seconds       = $Seconds
            Elapsed       = $elapsed
            Threads       = $Threads
            WheaAborted   = $aborted
            WheaError     = $wheaError
            WheaEventCount = @($whea).Count
            WheaEvents    = @($whea | ForEach-Object {
                [pscustomobject]@{
                    TimeCreated = $_.TimeCreated.ToString('o')
                    Id          = $_.Id
                    Level       = $_.LevelDisplayName
                    Provider    = $_.ProviderName
                    Message     = $_.Message
                }
            })
            Verdict       = $verdict
        }
        $out = Join-Path $ReportDir ('stability-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $out -Encoding UTF8
        Write-Bnqq ('Relatorio: {0}' -f $out) 'OK'
    }
}
