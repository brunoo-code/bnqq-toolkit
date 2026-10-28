if (-not ('Bnqq.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Bnqq {
    public static class Native {
        [DllImport("ntdll.dll")]
        public static extern int NtSuspendProcess(IntPtr handle);

        [DllImport("ntdll.dll")]
        public static extern int NtResumeProcess(IntPtr handle);

        [DllImport("ntdll.dll")]
        public static extern int NtSetInformationProcess(IntPtr handle, int infoClass, ref int info, int length);

        [DllImport("psapi.dll")]
        public static extern bool EmptyWorkingSet(IntPtr handle);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr handle);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    }
}
'@
}

$script:FocusStateFile = $null

$script:ProtectedProcesses = @(
    'System', 'Idle', 'Registry', 'Memory Compression', 'csrss', 'wininit', 'services',
    'lsass', 'smss', 'winlogon', 'dwm', 'explorer', 'audiodg', 'svchost', 'fontdrvhost',
    'MsMpEng', 'NisSrv', 'SecurityHealthService', 'vgc', 'vgk', 'BEDaisy', 'EasyAntiCheat',
    'lsass', 'spoolsv', 'WUDFHost', 'dllhost', 'sihost', 'taskhostw', 'ctfmon',
    'Steam', 'steam', 'steamwebhelper', 'Discord', 'DiscordCanary',
    'cs2', 'VALORANT-Win64-Shipping', 'RiotClientServices'
)

$script:SuspendablePatterns = @(
    'msedge', 'msedgewebview2', 'chrome', 'brave', 'firefox', 'opera', 'vivaldi',
    'OneDrive', 'Dropbox', 'GoogleDriveFS', 'pCloud', 'MEGAsync',
    'Teams', 'ms-teams', 'WhatsApp', 'Telegram',
    'EpicGamesLauncher', 'Battle.net', 'Origin', 'UbisoftConnect', 'GalaxyClient',
    'Docker Desktop', 'com.docker.backend', 'com.docker.build', 'vmmem', 'vmmemWSL',
    'RobloxPlayerBeta', 'Spotify', 'Notion', 'Slack', 'Zoom'
)

function Get-BnqqForegroundPid {
    $hwnd = [Bnqq.Native]::GetForegroundWindow()
    $pid = [uint32]0
    [void][Bnqq.Native]::GetWindowThreadProcessId($hwnd, [ref]$pid)
    return [int]$pid
}

function Open-BnqqProcess {
    param([int]$ProcessId, [uint32]$Access = 0x0800)

    return [Bnqq.Native]::OpenProcess($Access, $false, $ProcessId)
}

function Suspend-BnqqProcess {
    param([int]$ProcessId)

    $handle = Open-BnqqProcess -ProcessId $ProcessId -Access 0x0800
    if ($handle -eq [IntPtr]::Zero) { return $false }

    try {
        return ([Bnqq.Native]::NtSuspendProcess($handle) -eq 0)
    }
    finally {
        [void][Bnqq.Native]::CloseHandle($handle)
    }
}

function Resume-BnqqProcess {
    param([int]$ProcessId)

    $handle = Open-BnqqProcess -ProcessId $ProcessId -Access 0x0800
    if ($handle -eq [IntPtr]::Zero) { return $false }

    try {
        return ([Bnqq.Native]::NtResumeProcess($handle) -eq 0)
    }
    finally {
        [void][Bnqq.Native]::CloseHandle($handle)
    }
}

function Set-BnqqIoPriority {
    param([int]$ProcessId, [ValidateSet('VeryLow', 'Low', 'Normal', 'High', 'Critical')] [string]$Level = 'High')

    $map = @{ VeryLow = 0; Low = 1; Normal = 2; High = 3; Critical = 4 }
    $value = $map[$Level]

    $handle = Open-BnqqProcess -ProcessId $ProcessId -Access 0x0200
    if ($handle -eq [IntPtr]::Zero) { return $false }

    try {
        return ([Bnqq.Native]::NtSetInformationProcess($handle, 33, [ref]$value, 4) -eq 0)
    }
    finally {
        [void][Bnqq.Native]::CloseHandle($handle)
    }
}

function Invoke-BnqqTrim {
    param([int]$MinMB = 150)

    $fg = Get-BnqqForegroundPid
    $freed = 0
    $count = 0

    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($p.Id -eq $fg -or $p.Id -eq $PID) { continue }
        if ($script:ProtectedProcesses -contains $p.ProcessName) { continue }
        if ($p.WorkingSet64 -lt ($MinMB * 1MB)) { continue }

        $handle = Open-BnqqProcess -ProcessId $p.Id -Access 0x0100 -bor 0x0400
        if ($handle -eq [IntPtr]::Zero) { continue }

        $before = $p.WorkingSet64
        try {
            if ([Bnqq.Native]::EmptyWorkingSet($handle)) {
                $after = (Get-Process -Id $p.Id -ErrorAction SilentlyContinue).WorkingSet64
                if ($after -and $after -lt $before) {
                    $freed += ($before - $after)
                    $count++
                }
            }
        }
        finally {
            [void][Bnqq.Native]::CloseHandle($handle)
        }
    }

    Write-Bnqq ('{0} processo(s) trimado(s), {1} MB liberados' -f $count, [math]::Round($freed / 1MB, 0)) 'OK'
    return [math]::Round($freed / 1MB, 0)
}

function Invoke-BnqqRebalance {
    param([int]$Seconds = 60, [int]$Threshold = 15)

    Write-Bnqq ('ProBalance por {0}s (limite {1}% CPU)' -f $Seconds, $Threshold) 'STEP'

    $state = @{}
    $actions = 0
    $end = (Get-Date).AddSeconds($Seconds)

    while ((Get-Date) -lt $end) {
        $fg = Get-BnqqForegroundPid
        $procs = @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @('_Total', 'Idle') })

        foreach ($p in $procs) {
            $name = $p.Name -replace '#\d+$', ''
            if ($script:ProtectedProcesses -contains $name) { continue }
            if ($p.IDProcess -eq $fg -or $p.IDProcess -eq $PID) { continue }

            $live = Get-Process -Id $p.IDProcess -ErrorAction SilentlyContinue
            if (-not $live) { continue }
            if ($live.PriorityClass -ne 'Normal') { continue }

            $cpu = [double]$p.PercentProcessorTime
            $key = $p.IDProcess

            if (-not $state.ContainsKey($key)) {
                $state[$key] = [pscustomobject]@{ Hot = 0; Cold = 0; Lowered = $false; Name = $name }
            }
            $entry = $state[$key]

            if ($cpu -ge $Threshold) {
                $entry.Hot++
                $entry.Cold = 0

                if (-not $entry.Lowered -and $entry.Hot -ge 3) {
                    try {
                        $live.PriorityClass = 'BelowNormal'
                        [void](Set-BnqqIoPriority -ProcessId $p.IDProcess -Level 'Low')
                        $entry.Lowered = $true
                        $actions++
                        Write-Bnqq ('ProBalance: {0} ({1}) rebaixado - {2}% CPU' -f $name, $p.IDProcess, $cpu) 'INFO'
                    }
                    catch { }
                }
            }
            else {
                $entry.Cold++
                $entry.Hot = 0

                if ($entry.Lowered -and $entry.Cold -ge 6) {
                    try {
                        $live.PriorityClass = 'Normal'
                        [void](Set-BnqqIoPriority -ProcessId $p.IDProcess -Level 'Normal')
                        $entry.Lowered = $false
                        Write-Bnqq ('ProBalance: {0} restaurado' -f $name) 'INFO'
                    }
                    catch { }
                }
            }
        }

        Start-Sleep -Milliseconds 1500
    }

    foreach ($key in $state.Keys) {
        if (-not $state[$key].Lowered) { continue }
        $live = Get-Process -Id $key -ErrorAction SilentlyContinue
        if (-not $live) { continue }
        try { $live.PriorityClass = 'Normal' } catch { }
    }

    Write-Bnqq ('ProBalance encerrado: {0} ajuste(s)' -f $actions) 'OK'
}

function Get-BnqqRunningGame {
    $names = @(
        'cs2', 'VALORANT-Win64-Shipping', 'FortniteClient-Win64-Shipping', 'r5apex',
        'RainbowSix', 'Overwatch', 'RocketLeague', 'dota2', 'destiny2', 'cod',
        'GTA5', 'EscapeFromTarkov', 'TslGame', 'RustClient', 'DayZ_x64',
        'arma3_x64', 'SquadGame', 'DeadByDaylight-Win64-Shipping', 'PathOfExile',
        'warframe.x64', 'League of Legends'
    )

    foreach ($n in $names) {
        $p = Get-Process -Name $n -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p) { return $p }
    }

    return $null
}

function Start-BnqqFocus {
    param([string]$GameProcess)

    $game = if ($GameProcess) { Get-Process -Name $GameProcess -ErrorAction SilentlyContinue | Select-Object -First 1 } else { Get-BnqqRunningGame }
    if (-not $game) {
        Write-Bnqq 'Nenhum jogo em execucao detectado' 'WARN'
        return
    }

    Write-Bnqq ('Jogo: {0} (PID {1})' -f $game.ProcessName, $game.Id) 'STEP'

    $state = [pscustomobject]@{
        Created        = (Get-Date).ToString('o')
        Game           = $game.ProcessName
        GamePid        = $game.Id
        Suspended      = @()
        Lowered        = @()
        PausedServices = @()
        PowerPlan      = $null
    }

    $suspended = New-Object System.Collections.Generic.List[object]
    $lowered = New-Object System.Collections.Generic.List[object]

    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($p.Id -eq $game.Id -or $p.Id -eq $PID) { continue }
        if ($script:ProtectedProcesses -contains $p.ProcessName) { continue }

        $match = $false
        foreach ($pattern in $script:SuspendablePatterns) {
            if ($p.ProcessName -like $pattern) { $match = $true; break }
        }
        if (-not $match) { continue }

        try {
            if (Suspend-BnqqProcess -ProcessId $p.Id) {
                $suspended.Add([pscustomobject]@{ Id = $p.Id; Name = $p.ProcessName })
                Write-Bnqq ('Suspenso: {0} ({1})' -f $p.ProcessName, $p.Id) 'OK'
            }
        }
        catch { }
    }

    foreach ($name in @('Discord', 'Spotify', 'steamwebhelper')) {
        foreach ($p in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            try {
                $previous = $p.PriorityClass.ToString()
                $p.PriorityClass = 'BelowNormal'
                [void](Set-BnqqIoPriority -ProcessId $p.Id -Level 'Low')
                $lowered.Add([pscustomobject]@{ Id = $p.Id; Name = $p.ProcessName; Previous = $previous })
            }
            catch { }
        }
    }

    try {
        $game.PriorityClass = 'High'
        [void](Set-BnqqIoPriority -ProcessId $game.Id -Level 'High')
        Write-Bnqq 'Jogo em prioridade High e I/O High' 'OK'
    }
    catch {
        Write-Bnqq 'Nao foi possivel elevar a prioridade do jogo (anticheat?)' 'WARN'
    }

    $pausedServices = New-Object System.Collections.Generic.List[object]
    foreach ($name in @('DoSvc', 'BITS')) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc -or $svc.Status -ne 'Running') { continue }
        try {
            Stop-Service -Name $name -Force -ErrorAction Stop
            $pausedServices.Add([pscustomobject]@{ Name = $name })
            Write-Bnqq ('Pausado durante a partida: {0}' -f $name) 'OK'
        }
        catch { }
    }

    $scheme = (powercfg /getactivescheme) -join ' '
    $current = [regex]::Match($scheme, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
    $state.PowerPlan = $current

    $plan = (powercfg /list) -join "`n"
    $m = [regex]::Match($plan, '(?m)([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s+\((BNQQ [A-Za-z]+)\)')
    if ($m.Success) {
        powercfg /setactive $m.Groups[1].Value 2>$null | Out-Null
        Write-Bnqq ('Plano ativado: {0}' -f $m.Groups[2].Value) 'OK'
    }

    $state.Suspended = @($suspended)
    $state.Lowered = @($lowered)
    $state.PausedServices = @($pausedServices)

    if (-not $script:FocusStateFile) {
        $script:FocusStateFile = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'backups\focus-state.json'
    }
    $dir = Split-Path -Parent $script:FocusStateFile
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:FocusStateFile -Encoding UTF8

    Write-Bnqq ('Focus ativo: {0} suspenso(s), {1} rebaixado(s)' -f $suspended.Count, $lowered.Count) 'STEP'
    Write-Bnqq 'Ao terminar, rode: .\bnqq.ps1 unfocus' 'INFO'
}

function Stop-BnqqFocus {
    if (-not $script:FocusStateFile) {
        $script:FocusStateFile = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'backups\focus-state.json'
    }

    if (-not (Test-Path -LiteralPath $script:FocusStateFile)) {
        Write-Bnqq 'Nenhum estado de focus salvo' 'WARN'
        return
    }

    $state = Get-Content -LiteralPath $script:FocusStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $resumed = 0

    foreach ($s in @($state.Suspended)) {
        if (Resume-BnqqProcess -ProcessId $s.Id) { $resumed++ }
    }

    foreach ($l in @($state.Lowered)) {
        $p = Get-Process -Id $l.Id -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        try {
            $p.PriorityClass = $l.Previous
            [void](Set-BnqqIoPriority -ProcessId $l.Id -Level 'Normal')
        }
        catch { }
    }

    foreach ($s in @($state.PausedServices)) {
        try {
            Start-Service -Name $s.Name -ErrorAction Stop
            Write-Bnqq ('Retomado: {0}' -f $s.Name) 'OK'
        }
        catch { }
    }

    if ($state.PowerPlan) {
        powercfg /setactive $state.PowerPlan 2>$null | Out-Null
    }

    Remove-Item -LiteralPath $script:FocusStateFile -Force -ErrorAction SilentlyContinue

    Write-Bnqq ('{0} processo(s) retomado(s), prioridades restauradas' -f $resumed) 'OK'
}

function Show-BnqqFocus {
    if (-not $script:FocusStateFile) {
        $script:FocusStateFile = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'backups\focus-state.json'
    }

    if (-not (Test-Path -LiteralPath $script:FocusStateFile)) {
        Write-Host ''
        Write-Host '  FOCUS  |  inativo' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $state = Get-Content -LiteralPath $script:FocusStateFile -Raw -Encoding UTF8 | ConvertFrom-Json

    Write-Host ''
    Write-Host '  FOCUS  |  ativo' -ForegroundColor Cyan
    Write-Host ('    Jogo        {0} (PID {1})' -f $state.Game, $state.GamePid) -ForegroundColor Gray
    Write-Host ('    Suspensos   {0}' -f @($state.Suspended).Count) -ForegroundColor Gray
    Write-Host ('    Rebaixados  {0}' -f @($state.Lowered).Count) -ForegroundColor Gray
    Write-Host ''
}

function Invoke-BnqqStress {
    param([int]$Seconds = 15)

    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $threads = [int]$cpu.NumberOfLogicalProcessors
    $base = [int]$cpu.MaxClockSpeed

    Write-Bnqq ('Carga em {0} threads por {1}s...' -f $threads, $Seconds) 'STEP'

    $jobs = @()
    for ($i = 0; $i -lt $threads; $i++) {
        $jobs += Start-Job -ScriptBlock {
            param($Until)
            $x = 0.0
            while ((Get-Date) -lt $Until) {
                $x = [math]::Sqrt($x + 1.0) * 1.000001
                if ($x -gt 1000) { $x = 0 }
            }
        } -ArgumentList ((Get-Date).AddSeconds($Seconds))
    }

    Start-Sleep -Seconds 3
    $peak = 0
    $samples = New-Object System.Collections.Generic.List[double]
    $end = (Get-Date).AddSeconds($Seconds - 3)

    while ((Get-Date) -lt $end) {
        $info = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
        if ($info) {
            $perf = [double]$info.PercentProcessorPerformance
            $samples.Add($perf)
            if ($perf -gt $peak) { $peak = $perf }
        }
        Start-Sleep -Milliseconds 800
    }

    $jobs | Stop-Job -ErrorAction SilentlyContinue
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue

    $sustained = if ($samples.Count -gt 0) { ($samples | Measure-Object -Average).Average } else { 0 }
    $drop = if ($peak -gt 0) { [math]::Round((1 - ($sustained / $peak)) * 100, 1) } else { 0 }
    $mhz = [math]::Round($base * ($sustained / 100), 0)

    Write-Host ''
    Write-Host '  STRESS / SUSTENTACAO' -ForegroundColor Cyan
    Write-Host ('    Clock base       {0} MHz' -f $base) -ForegroundColor Gray
    Write-Host ('    Performance pico {0}%' -f [math]::Round($peak, 0)) -ForegroundColor Gray
    Write-Host ('    Performance media{0}%  (~{1} MHz)' -f [math]::Round($sustained, 0), $mhz) -ForegroundColor Gray
    $color = if ($drop -gt 12) { 'Red' } elseif ($drop -gt 6) { 'Yellow' } else { 'Green' }
    Write-Host ('    Queda sob carga  {0}%' -f $drop) -ForegroundColor $color
    if ($drop -gt 12) {
        Write-Host '    Throttling termico ou limite de VRM. Verifique cooler e curva de ventoinha.' -ForegroundColor Yellow
    }
    elseif ($drop -gt 6) {
        Write-Host '    Queda moderada. Normal em gabinetes compactos.' -ForegroundColor DarkYellow
    }
    else {
        Write-Host '    Boost sustentado. CPU saudavel para competitivo.' -ForegroundColor Green
    }
    Write-Host ''
}
