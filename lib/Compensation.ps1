function Get-BnqqVbsState {
    $dg = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
    $hvciPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
    $vbs = (Get-ItemProperty -LiteralPath $dg -Name EnableVirtualizationBasedSecurity -ErrorAction SilentlyContinue).EnableVirtualizationBasedSecurity
    $hvci = (Get-ItemProperty -LiteralPath $hvciPath -Name Enabled -ErrorAction SilentlyContinue).Enabled
    $platform = (Get-ItemProperty -LiteralPath $dg -Name RequirePlatformSecurityFeatures -ErrorAction SilentlyContinue).RequirePlatformSecurityFeatures

    $hypervisor = 'indisponivel'
    try {
        $bcd = (@(& bcdedit /enum '{current}' 2>$null) -join "`n")
        if ($bcd -match '(?im)^\s*hypervisorlaunchtype\s+(\S+)') { $hypervisor = $Matches[1] }
    }
    catch { }

    $runtime = $null
    try {
        $runtime = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop
    }
    catch { }

    $runtimeStatus = if ($runtime) { $runtime.VirtualizationBasedSecurityStatus } else { $null }
    $services = if ($runtime) { @($runtime.SecurityServicesRunning) } else { @() }
    $active = ($vbs -eq 1) -and ($hvci -eq 1) -and ($hypervisor -match '^auto$')

    return [pscustomobject]@{
        VbsRegistry = $vbs
        HvciRegistry = $hvci
        PlatformSecurity = $platform
        HypervisorLaunch = $hypervisor
        RuntimeStatus = $runtimeStatus
        RuntimeServices = $services
        HvciRunning = $services -contains 2
        Configured = $active
        Note = 'VBS/HVCI sao obrigatorios para Valorant/FACEIT; nao ha bypass de estado'
    }
}

function Set-BnqqVbsOn {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para habilitar VBS/HVCI' }

    & bcdedit /set hypervisorlaunchtype auto 2>$null | Out-Null
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 1 'DWord'
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'RequirePlatformSecurityFeatures' 1 'DWord'
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 1 'DWord'
    Set-BnqqMeta 'VbsRequired' $true
    Write-Bnqq 'VBS/HVCI habilitados; hypervisorlaunchtype=auto (reboot)' 'OK'
}

function Set-BnqqUsbInputPriority {
    $controllers = @(Get-PnpDevice -Class USB -Status OK -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like 'PCI\*' })
    $logical = [int](Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).NumberOfLogicalProcessors
    $usbCpu = if ($logical -gt 1) { $logical - 1 } else { 0 }
    $mask = New-BnqqAffinityMask -Cpus @($usbCpu)
    $changed = 0

    foreach ($dev in $controllers) {
        $msi = Get-BnqqDeviceKey $dev.InstanceId 'MessageSignaledInterruptProperties'
        if (Test-Path -LiteralPath $msi) {
            Set-BnqqReg $msi 'MSISupported' 1 'DWord'
            Set-BnqqReg $msi 'DevicePriority' 3 'DWord'
            $changed++
        }

        $aff = Get-BnqqDeviceKey $dev.InstanceId 'Affinity Policy'
        if (Test-Path -LiteralPath $aff) {
            Set-BnqqReg $aff 'DevicePolicy' 4 'DWord'
            Set-BnqqReg $aff 'AssignmentSetOverride' $mask 'Binary'
        }
    }

    if ($changed -gt 0) {
        Write-Bnqq ('USB: MSI/prioridade 3 em {0} controladora(s); IRQ no CPU {1}' -f $changed, $usbCpu) 'OK'
    }
    else {
        Write-Bnqq 'USB: controladoras sem chave MSI editavel' 'INFO'
    }
}

function Set-BnqqInputCompensation {
    Set-BnqqKeyboardResponse
    Set-BnqqInputQueue
    Set-BnqqUsbPowerSaving
    Set-BnqqUsb3LinkPowerManagement 0

    Set-BnqqReg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'
    Set-BnqqReg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
    Set-BnqqReg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'
    Set-BnqqReg 'HKCU:\Control Panel\Mouse' 'MouseHoverTime' '0' 'String'
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout' '2000' 'String'

    Set-BnqqUsbInputPriority
    Write-Bnqq 'Input: aceleracao off, filas HID 20, USB sem suspensao, hover 0' 'OK'
    Write-Bnqq 'Input: MouseHoverTime e WaitToKill nao reduzem latencia de clique; sao apenas ajustes de shell/servico' 'INFO'
}

function Set-BnqqBackgroundCulling {
    $targets = @('DiagTrack', 'dmwappushservice', 'WECsvc', 'SysMain', 'WSearch')
    $store = @{}
    $changed = 0

    foreach ($name in $targets) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        if ($svc.StartType -ne 'Disabled') { $store[$name] = $svc.StartType.ToString() }
        try {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
            $changed++
            Write-Bnqq ('Background: {0} desativado' -f $name) 'OK'
        }
        catch {
            Write-Bnqq ('Background: nao foi possivel desativar {0}' -f $name) 'WARN'
        }
    }

    if ($store.Count -gt 0) {
        $dir = Join-Path $script:BnqqRoot 'backups'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $file = Join-Path $dir ('background-services-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $store | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $file -Encoding UTF8
        Write-Bnqq ('Background: backup em {0}' -f $file) 'INFO'
    }

    try {
        $freed = Clear-BnqqStandbyList -Quiet
        if ($freed) { Write-Bnqq 'Standby list purgada' 'OK' }
        else { Write-Bnqq 'Standby purge indisponivel ou desnecessaria' 'INFO' }
    }
    catch {
        Write-Bnqq ('Standby purge falhou: {0}' -f $_.Exception.Message) 'WARN'
    }

    Write-Bnqq ('Background: {0} servico(s) desativado(s); WSearch/SysMain exigem reboot ou logoff para efeito completo' -f $changed) 'STEP'
}

function Set-BnqqDisplayCompensation {
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 'DWord'
    Set-BnqqDisplayOptimizations
    try { Set-BnqqVanguardDisplay } catch { }
    Write-Bnqq 'Display: HAGS=2, VRR/swap effect e FSO verificados (reboot)' 'OK'
    Write-Bnqq 'Display: HAGS nao garante fila zero no DWM; o ganho depende do driver e do jogo' 'INFO'
}

function Set-BnqqPowerCompensation {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para ajustar energia' }

    $guid = [regex]::Match(((powercfg /getactivescheme) -join ' '), '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
    if (-not $guid) { throw 'Plano de energia ativo nao identificado' }

    powercfg /setacvalueindex $guid SUB_PROCESSOR PROCTHROTTLEMIN 100 2>$null | Out-Null
    powercfg /setacvalueindex $guid SUB_PROCESSOR PROCTHROTTLEMAX 100 2>$null | Out-Null
    powercfg /setacvalueindex $guid SUB_PROCESSOR PERFBOOSTMODE 2 2>$null | Out-Null
    powercfg /setactive $guid 2>$null | Out-Null

    Set-BnqqCoreParking 100
    Set-BnqqPremiumPowerSettings
    Set-BnqqCStates 1
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1 'DWord'

    Write-Bnqq 'Power: core parking off, min/max 100%, idle demote/promote 100, C-states off' 'OK'
    Write-Bnqq 'Power: C-states efetivos dependem do firmware AMD; o Windows apenas solicita idle disable' 'INFO'
}

function Set-BnqqTcpCompensation {
    $store = @{}
    $changed = 0

    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $guid = $adapter.InterfaceGuid
        if (-not $guid) { continue }
        $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{0}' -f $guid
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $oldAck = (Get-ItemProperty -LiteralPath $path -Name TcpAckFrequency -ErrorAction SilentlyContinue).TcpAckFrequency
        $oldNoDelay = (Get-ItemProperty -LiteralPath $path -Name TCPNoDelay -ErrorAction SilentlyContinue).TCPNoDelay
        $store[$adapter.Name] = @{ TcpAckFrequency = $oldAck; TCPNoDelay = $oldNoDelay }

        Set-BnqqReg $path 'TcpAckFrequency' 1 'DWord'
        Set-BnqqReg $path 'TCPNoDelay' 1 'DWord'
        $changed++
        Write-Bnqq ('TCP: Nagle/ACK imediato em {0}' -f $adapter.Name) 'OK'
    }

    if ($store.Count -gt 0) { Set-BnqqMeta 'TcpInterfaceTweaks' $store }
    if ($changed -eq 0) { Write-Bnqq 'TCP: nenhuma interface ativa elegivel' 'WARN' }
    Set-BnqqTcpTuning
    Write-Bnqq 'TCP: TcpAckFrequency=1/TCPNoDelay=1; isso aumenta ACKs e nao e ideal em todo link' 'INFO'
}

function Set-BnqqGpuCacheCompensation {
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 'DWord'
    $shader = Get-BnqqShaderCacheStatus
    Write-Bnqq 'GPU: HAGS ligado; cache de shader permanece sob controle do driver' 'OK'
    Write-Bnqq ('GPU: cache atual {0} MB; nao existe tamanho ilimitado por registro suportado' -f $shader.TotalMB) 'INFO'
}

function Set-BnqqCompensation {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para aplicar a compensacao VBS/HVCI' }

    Set-BnqqVbsOn
    $preflight = Get-BnqqSecurityPreflight
    if (-not $preflight.ReadyForVanguard) {
        Write-Bnqq 'Preflight: Secure Boot/TPM/VBS/HVCI ainda nao estao 100% prontos; reboot ou ajuste de firmware pode ser necessario' 'WARN'
    }
    Set-BnqqInputCompensation
    Set-BnqqHidRuntime -QueueSize 20
    Set-BnqqBackgroundCulling
    Set-BnqqDisplayCompensation
    Set-BnqqPowerCompensation
    Set-BnqqTcpCompensation
    Set-BnqqGpuCacheCompensation
    Set-BnqqMsiTargets
    Set-BnqqAcpiTimer

    $task = Get-BnqqWatcherTask
    $action = if ($task -and $task.Actions.Count -gt 0) { [string]$task.Actions[0].Arguments } else { '' }
    if (-not $task -or $action -notmatch '-PinPhysical' -or $action -notmatch '-DeepFreeze') {
        Install-BnqqWatcher -PinPhysical -DeepFreeze
    }
    elseif ($task.State -ne 'Running') {
        Start-ScheduledTask -TaskName 'BNQQ Game Watcher' -ErrorAction SilentlyContinue
    }

    Set-BnqqMeta 'CompensationApplied' $true
    Write-Bnqq 'Compensacao VBS/HVCI aplicada: jogo 0x5555, background 0xAAAA, timer TSC, MSI, input e rede' 'OK'
    Write-Bnqq 'Reboot necessario para VBS/HVCI, HAGS e parte dos drivers' 'WARN'
}

function Get-BnqqCompensationStatus {
    $vbs = Get-BnqqVbsState
    $timer = Get-BnqqTimerResolution
    $acpi = Get-BnqqAcpiTimerStatus
    $msi = Get-BnqqMsiStatus
    $watcher = Get-BnqqWatcherTask
    $hags = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -ErrorAction SilentlyContinue).HwSchMode
    $mouse = Get-ItemProperty 'HKCU:\Control Panel\Mouse' -ErrorAction SilentlyContinue
    $services = @{}
    foreach ($name in @('DiagTrack', 'dmwappushservice', 'WECsvc', 'SysMain', 'WSearch')) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) { $services[$name] = $svc.StartType.ToString() }
    }
    $tcp = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
        $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{0}' -f $_.InterfaceGuid
        $props = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue
        [pscustomobject]@{ Name = $_.Name; Ack = $props.TcpAckFrequency; NoDelay = $props.TCPNoDelay }
    })

    return [pscustomobject]@{
        Vbs = $vbs
        Timer = $timer
        Acpi = $acpi
        Msi = $msi
        WatcherState = if ($watcher) { $watcher.State } else { 'ausente' }
        Hags = $hags
        MouseSpeed = $mouse.MouseSpeed
        MouseHoverTime = $mouse.MouseHoverTime
        Services = $services
        Tcp = $tcp
        Shader = Get-BnqqShaderCacheStatus
    }
}

function Show-BnqqCompensationStatus {
    param($Status)
    if (-not $Status) { $Status = Get-BnqqCompensationStatus }

    Write-Host ''
    Write-Host '  COMPENSACAO VBS / HVCI' -ForegroundColor Cyan
    Write-Host ('    VBS reg      {0} · HVCI reg {1} · hypervisor {2}' -f $Status.Vbs.VbsRegistry, $Status.Vbs.HvciRegistry, $Status.Vbs.HypervisorLaunch) -ForegroundColor Gray
    Write-Host ('    Runtime      VBS={0} · HVCI rodando={1}' -f $Status.Vbs.RuntimeStatus, $Status.Vbs.HvciRunning) -ForegroundColor Gray
    Write-Host ('    Timer        {0:N3} ms · TSC={1}' -f $Status.Timer.CurrentMs, $Status.Acpi.TscSelected) -ForegroundColor Gray
    Write-Host ('    Watcher      {0} · HAGS {1}' -f $Status.WatcherState, $Status.Hags) -ForegroundColor Gray
    Write-Host ('    Mouse        speed {0} · hover {1}' -f $Status.MouseSpeed, $Status.MouseHoverTime) -ForegroundColor Gray
    Write-Host '    Servicos     ' -NoNewline
    foreach ($key in $Status.Services.Keys) { Write-Host ('{0}={1} ' -f $key, $Status.Services[$key]) -NoNewline -ForegroundColor Gray }
    Write-Host ''
    foreach ($row in $Status.Tcp) {
        Write-Host ('    TCP {0,-20} Ack={1} NoDelay={2}' -f $row.Name, $row.Ack, $row.NoDelay) -ForegroundColor Gray
    }
    Write-Host ('    Shader cache {0} MB (driver controla o tamanho)' -f $Status.Shader.TotalMB) -ForegroundColor Gray
    $gpuMsi = if ($Status.Msi.Rows.Count -ge 1) { $Status.Msi.Rows[0].Msi } else { 'n/d' }
    $nicMsi = if ($Status.Msi.Rows.Count -ge 2) { $Status.Msi.Rows[1].Msi } else { 'n/d' }
    Write-Host ('    MSI GPU={0} · rede={1}' -f $gpuMsi, $nicMsi) -ForegroundColor Gray
    Write-Host '    VBS/HVCI nao sao desligados por este modo; nao existe bypass de estado' -ForegroundColor DarkGray
    Write-Host ''
}
