function Reset-BnqqTimerDefaults {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao' }

    foreach ($value in @('useplatformclock', 'disabledynamictick', 'useplatformtick', 'tscsyncpolicy', 'x2apicpolicy', 'uselegacyapicmode')) {
        & bcdedit /deletevalue $value 2>$null | Out-Null
    }

    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Services\msisadrv' 'Start' 0
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 0

    Write-Bnqq 'BCD limpo: Windows volta a escolher o timer (TSC) sozinho' 'OK'
}

function Set-BnqqCredentialGuardOff {
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'LsaCfgFlags' 0
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'RequirePlatformSecurityFeatures' 0
    Write-Bnqq 'Credential Guard desativado' 'OK'
}

function Set-BnqqKeyboardResponse {
    $kb = 'HKCU:\Control Panel\Keyboard'
    Set-BnqqReg $kb 'KeyboardDelay' '0' 'String'
    Set-BnqqReg $kb 'KeyboardSpeed' '31' 'String'

    foreach ($acc in @('StickyKeys', 'ToggleKeys', 'FilterKeys')) {
        $path = 'HKCU:\Control Panel\Accessibility\{0}' -f $acc
        if ($acc -eq 'StickyKeys') { Set-BnqqReg $path 'Flags' '506' 'String' }
        if ($acc -eq 'ToggleKeys') { Set-BnqqReg $path 'Flags' '62' 'String' }
        if ($acc -eq 'FilterKeys') { Set-BnqqReg $path 'Flags' '122' 'String' }
    }

    Write-Bnqq 'Teclado: repeat delay 0, rate 31, teclas de aderencia sem atalho' 'OK'
}

function Set-BnqqBackgroundAppsOff {
    Set-BnqqReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
    Set-BnqqReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 0
    Set-BnqqReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2
    Write-Bnqq 'Apps em segundo plano desativados globalmente' 'OK'
}

function Get-BnqqSteamLibraries {
    $paths = New-Object System.Collections.Generic.List[string]

    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
    if ($steam -and (Test-Path -LiteralPath $steam)) { $paths.Add($steam) }

    if ($steam) {
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            $text = Get-Content -LiteralPath $vdf -Raw -ErrorAction SilentlyContinue
            foreach ($m in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
                $p = $m.Groups[1].Value -replace '\\\\', '\'
                if (-not $paths.Contains($p)) { $paths.Add($p) }
            }
        }
    }

    return $paths
}

function Get-BnqqGameExes {
    $names = @(
        'cs2.exe'
        'VALORANT-Win64-Shipping.exe'
        'FortniteClient-Win64-Shipping.exe'
        'r5apex.exe'
        'RainbowSix.exe'
        'Overwatch.exe'
        'RocketLeague.exe'
        'dota2.exe'
        'destiny2.exe'
        'cod.exe'
        'GTA5.exe'
        'EscapeFromTarkov.exe'
        'TslGame.exe'
        'RustClient.exe'
        'DayZ_x64.exe'
        'arma3_x64.exe'
        'SquadGame.exe'
        'DeadByDaylight-Win64-Shipping.exe'
        'League of Legends.exe'
        'PathOfExile.exe'
        'warframe.x64.exe'
    )

    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($lib in Get-BnqqSteamLibraries) {
        $common = Join-Path $lib 'steamapps\common'
        if (Test-Path -LiteralPath $common) { $roots.Add($common) }
    }
    foreach ($r in @(
        'C:\Riot Games'
        'C:\Program Files\Riot Games'
        'C:\Program Files\Epic Games'
        'C:\Program Files (x86)\Epic Games'
        'C:\Program Files (x86)\Battle.net'
        'C:\Program Files (x86)\Ubisoft'
        'C:\Games'
        'D:\Games'
        'D:\SteamLibrary\steamapps\common'
        'E:\SteamLibrary\steamapps\common'
    )) {
        if (Test-Path -LiteralPath $r) { $roots.Add($r) }
    }

    $found = New-Object System.Collections.Generic.List[string]

    foreach ($root in $roots) {
        foreach ($name in $names) {
            $hits = @(Get-ChildItem -LiteralPath $root -Filter $name -Recurse -Depth 4 -File -ErrorAction SilentlyContinue)
            foreach ($h in $hits) {
                if (-not $found.Contains($h.FullName)) { $found.Add($h.FullName) }
            }
        }
    }

    return $found
}

function Set-BnqqFullscreenOptimizations {
    $layers = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    $exes = @(Get-BnqqGameExes)
    $changed = 0

    foreach ($exe in $exes) {
        $current = (Get-ItemProperty -LiteralPath $layers -Name $exe -ErrorAction SilentlyContinue).$exe
        if ($current -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE') { continue }

        $value = if ($current) { '{0} DISABLEDXMAXIMIZEDWINDOWEDMODE' -f $current } else { '~ DISABLEDXMAXIMIZEDWINDOWEDMODE' }
        Set-BnqqReg $layers $exe $value 'String'
        $changed++
        Write-Bnqq ('Fullscreen exclusivo forcado: {0}' -f (Split-Path $exe -Leaf)) 'OK'
    }

    Write-Bnqq ('{0} executavel(is) de jogo ajustado(s)' -f $changed) 'STEP'
}

function Set-BnqqSteamOverlayOff {
    $steam = 'HKCU:\Software\Valve\Steam'
    if (-not (Test-Path -LiteralPath $steam)) {
        Write-Bnqq 'Steam nao instalado para este usuario' 'INFO'
        return
    }

    Set-BnqqReg $steam 'GameOverlayEnabled' 0
    Set-BnqqReg $steam 'GameOverlayFPSEnabled' 0
    Write-Bnqq 'Steam: overlay e contador de FPS desativados' 'OK'
}

function Set-BnqqTcpTuning {
    & netsh int tcp set global rss=enabled 2>$null | Out-Null
    & netsh int tcp set global ecncapability=disabled 2>$null | Out-Null
    & netsh int tcp set global timestamps=disabled 2>$null | Out-Null
    & netsh int tcp set global autotuninglevel=normal 2>$null | Out-Null
    & netsh int tcp set global initialRto=2000 2>$null | Out-Null
    & netsh int tcp set global nonsackrttresiliency=disabled 2>$null | Out-Null
    Write-Bnqq 'TCP: ECN e timestamps off, RTO inicial 2000 ms' 'OK'
}

function Set-BnqqDnsFast {
    $servers = @('1.1.1.1', '1.0.0.1')
    $store = @{}
    $changed = 0

    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $current = @(Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
        $existing = @($current | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
        if (($existing -join ',') -eq ($servers -join ',')) { continue }

        $store[$adapter.Name] = $existing
        try {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $servers -ErrorAction Stop
            $changed++
        }
        catch { }
    }

    if ($store.Count -gt 0) { Set-BnqqMeta 'Dns' $store }
    Write-Bnqq ('DNS Cloudflare aplicado em {0} adaptador(es)' -f $changed) 'OK'
}

function Set-BnqqReservedStorageOff {
    $out = & dism /Online /Get-ReservedStorageState 2>$null
    if (($out -join ' ') -match 'Disabled') {
        Write-Bnqq 'Reserved Storage ja esta desativado' 'INFO'
        return
    }

    & dism /Online /Set-ReservedStorageState /State:Disabled 2>$null | Out-Null
    Write-Bnqq 'Reserved Storage desativado (libera espaco no sistema)' 'OK'
}

function Set-BnqqStartupLaunchers {
    $run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $props = Get-ItemProperty -LiteralPath $run -ErrorAction SilentlyContinue
    if (-not $props) { return }

    $patterns = @(
        'EpicGamesLauncher'
        'Battle.net'
        'Origin'
        'Ubisoft'
        'GalaxyClient'
        'Teams'
        'OneDrive'
        'Adobe'
        'Java'
        'Update'
        'Updater'
        'Razer'
        'Logi'
        'Cortex'
    )

    foreach ($p in $props.PSObject.Properties) {
        if ($p.Name -eq 'PSPath' -or $p.Name -eq 'PSParentPath' -or $p.Name -eq 'PSChildName' -or $p.Name -eq 'PSDrive' -or $p.Name -eq 'PSProvider') { continue }
        if ($p.Name -like 'MicrosoftEdgeAutoLaunch_*') { continue }

        $match = $false
        foreach ($pattern in $patterns) {
            if ($p.Name -like ('*' + $pattern + '*')) { $match = $true; break }
        }
        if (-not $match) { continue }

        Set-BnqqReg $run $p.Name $null
        Write-Bnqq ('Inicializacao removida: {0}' -f $p.Name) 'OK'
    }
}

function Clear-BnqqShaderCaches {
    $targets = @(
        (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache')
        (Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache')
        (Join-Path $env:LOCALAPPDATA 'NVIDIA Corporation\NV_Cache')
        (Join-Path $env:LOCALAPPDATA 'D3DSCache')
        (Join-Path $env:LOCALAPPDATA 'AMD\DxCache')
        (Join-Path $env:LOCALAPPDATA 'AMD\GLCache')
        (Join-Path $env:LOCALAPPDATA 'Intel\ShaderCache')
    )

    $freed = 0
    foreach ($dir in $targets) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $size = (Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        if ($size) { $freed += $size }
        Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Bnqq ('Cache limpo: {0}' -f $dir) 'OK'
    }

    Write-Bnqq ('{0} MB liberados' -f [math]::Round($freed / 1MB, 0)) 'STEP'
}

function Get-BnqqTier {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'Basic Display|Remote|Virtual' } |
        Sort-Object AdapterRAM -Descending | Select-Object -First 1
    $modules = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $disks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)

    $ramGB = [math]::Round((($modules | Measure-Object Capacity -Sum).Sum) / 1GB, 0)
    $threads = $cpu.NumberOfLogicalProcessors
    $hasSsd = @($disks | Where-Object { $_.MediaType -eq 'SSD' }).Count -gt 0

    $gpuName = if ($gpu) { $gpu.Name } else { '' }
    $weakGpu = $gpuName -match 'Intel.*Graphics|UHD|Vega [0-9]|GT [0-9]|GTX (6|7|9)[0-9]{2}|RX 5[0-9]{2}'

    $score = 0
    if ($ramGB -ge 8) { $score++ }
    if ($ramGB -ge 16) { $score++ }
    if ($hasSsd) { $score++ }
    if ($threads -ge 8) { $score++ }
    if ($threads -ge 12) { $score++ }
    if (-not $weakGpu) { $score++ }

    if ($score -le 2) { return 'low' }
    if ($score -le 4) { return 'mid' }
    return 'high'
}

function Invoke-BnqqBench {
    param([int]$Seconds = 10, [string]$ReportDir)

    $samples = New-Object System.Collections.Generic.List[object]
    $end = (Get-Date).AddSeconds($Seconds)

    Write-Bnqq ('Coletando {0}s de telemetria...' -f $Seconds) 'STEP'

    while ((Get-Date) -lt $end) {
        $cpu = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
        $sys = Get-CimInstance Win32_PerfFormattedData_PerfOS_System -ErrorAction SilentlyContinue
        $mem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
        $disk = Get-CimInstance Win32_PerfFormattedData_PerfDisk_LogicalDisk -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1

        $samples.Add([pscustomobject]@{
            CpuPct    = [double]$cpu.PercentProcessorTime
            CpuPerf   = [double]$cpu.PercentProcessorPerformance
            Queue     = [double]$sys.ProcessorQueueLength
            DiskQueue = if ($disk) { [double]$disk.AvgDiskQueueLength } else { 0 }
            AvailMB   = [double]$mem.AvailableMBytes
            PagesSec  = [double]$mem.PagesPerSec
        })

        Start-Sleep -Milliseconds 500
    }

    $avg = [pscustomobject]@{
        CpuPct    = [math]::Round(($samples | Measure-Object CpuPct -Average).Average, 1)
        CpuPerf   = [math]::Round(($samples | Measure-Object CpuPerf -Average).Average, 1)
        Queue     = [math]::Round(($samples | Measure-Object Queue -Average).Average, 2)
        DiskQueue = [math]::Round(($samples | Measure-Object DiskQueue -Average).Average, 2)
        AvailMB   = [math]::Round(($samples | Measure-Object AvailMB -Average).Average, 0)
        PagesSec  = [math]::Round(($samples | Measure-Object PagesSec -Average).Average, 1)
        Samples   = $samples.Count
    }

    Write-Host ''
    Write-Host '  BENCH (media da janela)' -ForegroundColor Cyan
    Write-Host ('    CPU uso          {0}%' -f $avg.CpuPct) -ForegroundColor Gray
    Write-Host ('    CPU performance  {0}%  (acima de 100 = boost)' -f $avg.CpuPerf) -ForegroundColor Gray
    Write-Host ('    Fila de CPU      {0}' -f $avg.Queue) -ForegroundColor $(if ($avg.Queue -gt 2) { 'Yellow' } else { 'Green' })
    Write-Host ('    Fila de disco    {0}' -f $avg.DiskQueue) -ForegroundColor $(if ($avg.DiskQueue -gt 2) { 'Yellow' } else { 'Green' })
    Write-Host ('    RAM disponivel   {0} MB' -f $avg.AvailMB) -ForegroundColor Gray
    Write-Host ('    Pages/s          {0}' -f $avg.PagesSec) -ForegroundColor $(if ($avg.PagesSec -gt 200) { 'Yellow' } else { 'Green' })
    Write-Host ''

    if ($ReportDir) {
        if (-not (Test-Path -LiteralPath $ReportDir)) { New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null }
        $file = Join-Path $ReportDir ('bench-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $avg | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $file -Encoding UTF8
        Write-Bnqq ('Relatorio: {0}' -f $file) 'OK'
    }

    return $avg
}

function Show-BnqqGuide {
    $tier = Get-BnqqTier
    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'Basic Display|Remote|Virtual' } |
        Sort-Object AdapterRAM -Descending | Select-Object -First 1

    $label = switch ($tier) {
        'low' { 'BAIXO' }
        'mid' { 'MEDIO' }
        'high' { 'ALTO' }
    }

    Write-Host ''
    Write-Host ('  GUIA COMPETITIVO  |  tier {0}' -f $label) -ForegroundColor Cyan
    Write-Host ''

    Write-Host '  CS2 - VIDEO' -ForegroundColor White
    if ($tier -eq 'low') {
        Write-Host '    Display Mode      Fullscreen' -ForegroundColor Gray
        Write-Host '    Resolucao         1280x960 4:3 esticado (ou 1024x768)' -ForegroundColor Gray
        Write-Host '    FSR               Quality (se disponivel)' -ForegroundColor Gray
        Write-Host '    Tudo em Low/Off, AA off, sombras Low' -ForegroundColor Gray
        Write-Host '    fps_max           0 (deixe o driver limitar)' -ForegroundColor Gray
    }
    elseif ($tier -eq 'mid') {
        Write-Host '    Display Mode      Fullscreen' -ForegroundColor Gray
        Write-Host '    Resolucao         1280x960 4:3 ou nativa' -ForegroundColor Gray
        Write-Host '    Sombras Low, AA 2x MSAA no maximo, resto Low' -ForegroundColor Gray
        Write-Host '    fps_max           0 ou ~2x o refresh' -ForegroundColor Gray
    }
    else {
        Write-Host '    Display Mode      Fullscreen' -ForegroundColor Gray
        Write-Host '    Resolucao         Nativa ou 4:3 esticado' -ForegroundColor Gray
        Write-Host '    Sombras Low, AA Off, texturas conforme VRAM' -ForegroundColor Gray
        Write-Host '    fps_max           ~3% abaixo do refresh (com VRR)' -ForegroundColor Gray
    }
    Write-Host ''

    Write-Host '  CS2 - LAUNCH OPTIONS' -ForegroundColor White
    if ($tier -eq 'low') {
        Write-Host '    -high -nojoy +fps_max 0 +mat_queue_mode 2 -softparticlesdefaultoff' -ForegroundColor Gray
        Write-Host '    +r_dynamic 0 +r_drawparticles 0 +cl_forcepreload 1' -ForegroundColor Gray
    }
    else {
        Write-Host '    -high -nojoy +fps_max 0 +mat_queue_mode 2 -softparticlesdefaultoff' -ForegroundColor Gray
    }
    Write-Host ''

    Write-Host '  VALORANT' -ForegroundColor White
    Write-Host '    Display Mode      Fullscreen' -ForegroundColor Gray
    Write-Host '    VSync             Off' -ForegroundColor Gray
    Write-Host '    NVIDIA Reflex     On + Boost' -ForegroundColor Gray
    Write-Host '    Material/Detail   Low, AA None, Anisotropic 1x' -ForegroundColor Gray
    Write-Host '    Raw Input Buffer  On' -ForegroundColor Gray
    Write-Host ''

    Write-Host '  NVIDIA APP (perfil do jogo)' -ForegroundColor White
    Write-Host '    Low Latency Mode        Ultra' -ForegroundColor Gray
    Write-Host '    Power Management        Prefer Maximum Performance' -ForegroundColor Gray
    Write-Host '    Texture Filtering       High Performance' -ForegroundColor Gray
    Write-Host '    Threaded Optimization   Auto' -ForegroundColor Gray
    if ($gpu -and $gpu.Name -match 'RTX') {
        Write-Host '    V-Sync                  Off (fixo) ou On com cap 3% abaixo (VRR)' -ForegroundColor Gray
    }
    else {
        Write-Host '    V-Sync                  Off' -ForegroundColor Gray
    }
    Write-Host ''

    Write-Host '  MOUSE / TECLADO' -ForegroundColor White
    Write-Host '    Polling                1000 Hz (2000 no maximo)' -ForegroundColor Gray
    Write-Host '    Angle snap / smoothing Off no software do mouse' -ForegroundColor Gray
    Write-Host '    Motion sync            Off se sentir atraso' -ForegroundColor Gray
    Write-Host '    Enhance pointer prec.  Off (ja aplicado)' -ForegroundColor Gray
    Write-Host ''
}
