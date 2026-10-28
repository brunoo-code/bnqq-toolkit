function Get-SystemInfo {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'Basic Display|Remote|Virtual|Parsec' } |
        Sort-Object AdapterRAM -Descending | Select-Object -First 1
    $modules = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $disks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    $enclosure = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue | Select-Object -First 1

    $laptopChassis = @(8, 9, 10, 14, 30, 31, 32)
    $isLaptop = $false
    if ($battery) { $isLaptop = $true }
    if ($enclosure -and $enclosure.ChassisTypes) {
        foreach ($t in $enclosure.ChassisTypes) {
            if ($laptopChassis -contains [int]$t) { $isLaptop = $true }
        }
    }

    $channels = @($modules | ForEach-Object {
        if ($_.DeviceLocator -match '([A-H])\d+$') { $Matches[1] } else { 'X' }
    } | Select-Object -Unique)

    $ramGB = [math]::Round((($modules | Measure-Object Capacity -Sum).Sum) / 1GB, 0)
    $ramSpeed = ($modules | Measure-Object ConfiguredClockSpeed -Maximum).Maximum

    $cpuVendor = 'unknown'
    if ($cpu.Manufacturer -match 'AMD') { $cpuVendor = 'amd' }
    elseif ($cpu.Manufacturer -match 'Intel') { $cpuVendor = 'intel' }

    $gpuVendor = 'unknown'
    if ($gpu) {
        if ($gpu.Name -match 'NVIDIA') { $gpuVendor = 'nvidia' }
        elseif ($gpu.Name -match 'AMD|Radeon') { $gpuVendor = 'amd' }
        elseif ($gpu.Name -match 'Intel') { $gpuVendor = 'intel' }
    }

    $hasSsd = $false
    $hasHdd = $false
    foreach ($d in $disks) {
        if ($d.MediaType -eq 'SSD') { $hasSsd = $true }
        if ($d.MediaType -eq 'HDD') { $hasHdd = $true }
    }

    $sysDrive = Get-Volume -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
    $freePct = if ($sysDrive -and $sysDrive.Size -gt 0) { [math]::Round(($sysDrive.SizeRemaining / $sysDrive.Size) * 100, 1) } else { $null }

    $planRaw = (powercfg /getactivescheme 2>$null) -join ' '
    $planName = [regex]::Match($planRaw, '\(([^)]+)\)').Groups[1].Value
    $planId = [regex]::Match($planRaw, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value

    $vbsStatus = $null
    try {
        $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
        $vbsStatus = $dg.VirtualizationBasedSecurityStatus
    }
    catch { }

    $hvci = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name Enabled -ErrorAction SilentlyContinue).Enabled
    $gameDvr = (Get-ItemProperty 'HKCU:\System\GameConfigStore' -Name GameDVR_Enabled -ErrorAction SilentlyContinue).GameDVR_Enabled
    $hags = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -ErrorAction SilentlyContinue).HwSchMode
    $throttle = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Name PowerThrottlingOff -ErrorAction SilentlyContinue).PowerThrottlingOff
    $mouseSpeed = (Get-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseSpeed -ErrorAction SilentlyContinue).MouseSpeed
    $pagefile = @(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue)
    $hiberboot = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled

    return [pscustomobject]@{
        OsCaption     = $os.Caption
        Build         = $os.BuildNumber
        CpuName       = $cpu.Name
        CpuVendor     = $cpuVendor
        Cores         = $cpu.NumberOfCores
        Threads       = $cpu.NumberOfLogicalProcessors
        BaseClock     = $cpu.MaxClockSpeed
        GpuName       = $gpu.Name
        GpuVendor     = $gpuVendor
        GpuDriver     = $gpu.DriverVersion
        RamGB         = $ramGB
        RamSpeed      = $ramSpeed
        RamChannels   = $channels.Count
        HasSsd        = $hasSsd
        HasHdd        = $hasHdd
        Disks         = @($disks | ForEach-Object { '{0} {1}GB {2}' -f $_.FriendlyName, [math]::Round($_.Size / 1GB, 0), $_.MediaType })
        IsLaptop      = $isLaptop
        RefreshRate   = $gpu.CurrentRefreshRate
        Resolution    = if ($gpu.CurrentHorizontalResolution) { '{0}x{1}' -f $gpu.CurrentHorizontalResolution, $gpu.CurrentVerticalResolution } else { '' }
        SystemFreePct = $freePct
        PowerPlan     = $planName
        PowerPlanId   = $planId
        VbsStatus     = $vbsStatus
        Hvci          = $hvci
        GameDvr       = $gameDvr
        Hags          = $hags
        PowerThrottle = $throttle
        MouseSpeed    = $mouseSpeed
        Pagefile      = $pagefile.Count
        FastStartup   = $hiberboot
        Hypervisor    = $cs.HypervisorPresent
    }
}

function Get-Applicability {
    param($System)

    return [pscustomobject]@{
        Desktop      = -not $System.IsLaptop
        Laptop       = $System.IsLaptop
        Nvidia       = $System.GpuVendor -eq 'nvidia'
        AmdGpu       = $System.GpuVendor -eq 'amd'
        IntelGpu     = $System.GpuVendor -eq 'intel'
        AmdCpu       = $System.CpuVendor -eq 'amd'
        IntelCpu     = $System.CpuVendor -eq 'intel'
        Ssd          = $System.HasSsd
        Hdd          = $System.HasHdd
        Ram16        = $System.RamGB -ge 16
        Ram32        = $System.RamGB -ge 32
        HighRefresh  = $System.RefreshRate -ge 120
        Win11        = [int]$System.Build -ge 22000
    }
}

function Test-TweakApplicable {
    param($Tweak, $System)

    if (-not $Tweak.Requires) { return $true }
    $req = $Tweak.Requires

    if ($req.Chassis -eq 'desktop' -and $System.IsLaptop) { return $false }
    if ($req.Chassis -eq 'laptop' -and -not $System.IsLaptop) { return $false }

    if ($req.Gpu -and $System.GpuVendor -ne $req.Gpu) { return $false }
    if ($req.Cpu -and $System.CpuVendor -ne $req.Cpu) { return $false }

    if ($req.MinRamGB -and $System.RamGB -lt $req.MinRamGB) { return $false }
    if ($req.MinBuild -and [int]$System.Build -lt $req.MinBuild) { return $false }
    if ($req.Storage -eq 'ssd' -and -not $System.HasSsd) { return $false }
    if ($req.Storage -eq 'hdd' -and -not $System.HasHdd) { return $false }

    return $true
}

function Get-Findings {
    param($System)

    $f = New-Object System.Collections.Generic.List[object]

    $add = {
        param($Area, $Severity, $Title, $Detail, $Action)
        $f.Add([pscustomobject]@{ Area = $Area; Severity = $Severity; Title = $Title; Detail = $Detail; Action = $Action })
    }

    if ($System.VbsStatus -eq 2 -and -not $System.IsLaptop) {
        & $add 'Latencia' 'WARN' 'VBS / HVCI ativo' 'Overhead de virtualizacao em cada syscall.' 'Desativar Core Isolation (desktop).'
    }

    if ($System.GameDvr -eq 1) {
        & $add 'Captura' 'WARN' 'Game DVR ativo' 'Gravacao em segundo plano.' 'Desativar.'
    }

    if ($System.PowerThrottle -ne 1) {
        & $add 'Latencia' 'WARN' 'Power Throttling ativo' 'Windows reduz clocks em segundo plano.' 'Desativar.'
    }

    if ($System.MouseSpeed -ne '0') {
        & $add 'Input' 'WARN' 'Aceleracao do mouse ativa' 'Movimento imprevisivel.' 'Desativar.'
    }

    if ($System.RamSpeed -and $System.RamSpeed -lt 2666) {
        & $add 'Memoria' 'WARN' ('RAM a {0} MT/s' -f $System.RamSpeed) 'XMP/DOCP provavelmente desligado.' 'Ativar no BIOS.'
    }

    if ($System.RamChannels -lt 2 -and $System.RamGB -ge 8) {
        & $add 'Memoria' 'WARN' 'Single channel' 'Largura de banda pela metade.' 'Instalar em canais distintos.'
    }

    if ($System.Pagefile -eq 0) {
        & $add 'Memoria' 'WARN' 'Pagefile desativado' 'Causa trim de working set.' 'Definir pagefile gerenciado.'
    }

    if ($System.FastStartup -eq 1) {
        & $add 'Sistema' 'WARN' 'Fast Startup ativo' 'Estado de driver inconsistente entre sessoes.' 'Desativar.'
    }

    if ($System.HasHdd) {
        & $add 'Disco' 'WARN' 'HDD presente' 'Jogos em HDD causam stutter.' 'Mover para SSD.'
    }

    if ($System.SystemFreePct -ne $null -and $System.SystemFreePct -lt 12) {
        & $add 'Disco' 'WARN' ('Sistema com {0}% livre' -f $System.SystemFreePct) 'SSD cheio perde desempenho.' 'Liberar espaco.'
    }

    if ($System.RefreshRate -and $System.RefreshRate -lt 100) {
        & $add 'Display' 'INFO' ('Monitor a {0} Hz' -f $System.RefreshRate) 'Abaixo do ideal para competitivo.' 'Verificar taxa maxima.'
    }

    if ($System.IsLaptop) {
        & $add 'Notebook' 'INFO' 'Chassi movel detectado' 'Perfil conservador aplicado automaticamente.' 'Nenhuma acao.'
    }

    return $f
}

function Show-Scan {
    param($System, $Findings)

    Write-Host ''
    Write-Host '  BNQQ TOOLKIT  |  SCAN' -ForegroundColor Cyan
    Write-Host ''

    Write-Host '  HARDWARE' -ForegroundColor White
    Write-Host ('    CPU      {0}  ({1}C/{2}T)' -f $System.CpuName.Trim(), $System.Cores, $System.Threads) -ForegroundColor Gray
    Write-Host ('    GPU      {0}' -f $System.GpuName) -ForegroundColor Gray
    Write-Host ('    RAM      {0} GB  {1} MT/s  {2} canal(is)' -f $System.RamGB, $System.RamSpeed, $System.RamChannels) -ForegroundColor Gray
    Write-Host ('    Chassi   {0}' -f $(if ($System.IsLaptop) { 'notebook' } else { 'desktop' })) -ForegroundColor Gray
    Write-Host ('    Display  {0} @ {1} Hz' -f $System.Resolution, $System.RefreshRate) -ForegroundColor Gray
    foreach ($d in $System.Disks) {
        Write-Host ('    Disco    {0}' -f $d) -ForegroundColor Gray
    }
    Write-Host ''

    Write-Host '  SISTEMA' -ForegroundColor White
    Write-Host ('    {0} build {1}' -f $System.OsCaption, $System.Build) -ForegroundColor Gray
    Write-Host ('    Plano    {0}' -f $System.PowerPlan) -ForegroundColor Gray
    Write-Host ''

    Write-Host '  ACHADOS' -ForegroundColor White
    foreach ($item in $Findings) {
        $color = switch ($item.Severity) {
            'WARN' { 'Yellow' }
            'INFO' { 'DarkGray' }
            default { 'Green' }
        }
        Write-Host ('    [{0}] {1}' -f $item.Severity, $item.Title) -ForegroundColor $color
        if ($item.Action -and $item.Severity -eq 'WARN') {
            Write-Host ('           -> {0}' -f $item.Action) -ForegroundColor DarkCyan
        }
    }
    Write-Host ''
}
