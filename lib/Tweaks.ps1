$script:TweakCatalog = @(
    @{
        Id = 'hvci-off'; Area = 'Latencia'; Risk = 'medium'; Reboot = $true
        Requires = @{ Chassis = 'desktop' }
        Name = 'Desativar Core Isolation (HVCI)'
        Apply = {
            Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
            Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
        }
    },
    @{
        Id = 'power-plan'; Area = 'CPU'; Risk = 'low'; Reboot = $false
        Name = 'Plano de energia adaptativo (desktop ou notebook)'
        Apply = { New-BnqqPowerPlan }
    },
    @{
        Id = 'gamedvr-off'; Area = 'Captura'; Risk = 'low'; Reboot = $false
        Name = 'Desativar Game DVR'
        Apply = {
            Set-BnqqReg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
            Set-BnqqReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
        }
    },
    @{
        Id = 'gamemode-on'; Area = 'Latencia'; Risk = 'low'; Reboot = $false
        Name = 'Ativar Game Mode'
        Apply = {
            Set-BnqqReg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
            Set-BnqqReg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
            Set-BnqqReg 'HKCU:\Software\Microsoft\GameBar' 'ShowStartupPanel' 0
            Set-BnqqReg 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 0
        }
    },
    @{
        Id = 'hags-on'; Area = 'GPU'; Risk = 'low'; Reboot = $true
        Requires = @{ MinBuild = 22000 }
        Name = 'Ativar HAGS'
        Apply = { Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 }
    },
    @{
        Id = 'power-throttling-off'; Area = 'Latencia'; Risk = 'low'; Reboot = $false
        Name = 'Desativar Power Throttling'
        Apply = { Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1 }
    },
    @{
        Id = 'win32-priority'; Area = 'CPU'; Risk = 'low'; Reboot = $false
        Name = 'Prioridade de foreground (Win32PrioritySeparation=26)'
        Apply = { Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 26 }
    },
    @{
        Id = 'mmcss-games'; Area = 'CPU'; Risk = 'low'; Reboot = $false
        Name = 'MMCSS: categoria Games em prioridade alta'
        Apply = {
            $base = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
            Set-BnqqReg $base 'GPU Priority' 8
            Set-BnqqReg $base 'Priority' 6
            Set-BnqqReg $base 'Scheduling Category' 'High' 'String'
            Set-BnqqReg $base 'SFIO Priority' 'High' 'String'
            Set-BnqqReg $base 'Clock Rate' 10000
        }
    },
    @{
        Id = 'network-throttling'; Area = 'Rede'; Risk = 'low'; Reboot = $false
        Name = 'Remover throttling de rede multimidia'
        Apply = {
            $base = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            Set-BnqqReg $base 'NetworkThrottlingIndex' 4294967295
            Set-BnqqReg $base 'SystemResponsiveness' 10
        }
    },
    @{
        Id = 'mouse-accel-off'; Area = 'Input'; Risk = 'low'; Reboot = $false
        Name = 'Desativar aceleracao do mouse (1:1)'
        Apply = {
            $base = 'HKCU:\Control Panel\Mouse'
            Set-BnqqReg $base 'MouseSpeed' '0' 'String'
            Set-BnqqReg $base 'MouseThreshold1' '0' 'String'
            Set-BnqqReg $base 'MouseThreshold2' '0' 'String'
            Set-BnqqReg $base 'SmoothMouseXCurve' ([byte[]]@(
                0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
                0x15,0x6E,0x00,0x00,0x00,0x00,0x00,0x00,
                0x00,0x40,0x01,0x00,0x00,0x00,0x00,0x00,
                0x29,0xDC,0x03,0x00,0x00,0x00,0x00,0x00,
                0x00,0x00,0x28,0x00,0x00,0x00,0x00,0x00)) 'Binary'
            Set-BnqqReg $base 'SmoothMouseYCurve' ([byte[]]@(
                0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
                0xFD,0x11,0x00,0x00,0x00,0x00,0x00,0x00,
                0x00,0x24,0x04,0x00,0x00,0x00,0x00,0x00,
                0x00,0x53,0x0A,0x00,0x00,0x00,0x00,0x00,
                0x00,0x00,0x38,0x00,0x00,0x00,0x00,0x00)) 'Binary'
        }
    },
    @{
        Id = 'fse-forced'; Area = 'Display'; Risk = 'low'; Reboot = $false
        Name = 'Forcar fullscreen exclusivo'
        Apply = {
            $base = 'HKCU:\System\GameConfigStore'
            Set-BnqqReg $base 'GameDVR_FSEBehaviorMode' 2
            Set-BnqqReg $base 'GameDVR_HonorUserFSEBehaviorMode' 1
            Set-BnqqReg $base 'GameDVR_DXGIHonorFSEWindowsCompatible' 1
            Set-BnqqReg $base 'GameDVR_EFSEFeatureFlags' 0
        }
    },
    @{
        Id = 'telemetry-off'; Area = 'Processos'; Risk = 'low'; Reboot = $false
        Name = 'Desativar telemetria'
        Apply = {
            Set-BnqqReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
            Set-BnqqServices -Names @('DiagTrack', 'dmwappushservice', 'MapsBroker', 'RetailDemo', 'WMPNetworkSvc')
        }
    },
    @{
        Id = 'ndu-off'; Area = 'Rede'; Risk = 'medium'; Reboot = $true
        Name = 'Desativar driver Ndu'
        Apply = { Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Services\Ndu' 'Start' 4 }
    },
    @{
        Id = 'mpo-off'; Area = 'Display'; Risk = 'medium'; Reboot = $true
        Name = 'Desativar MPO'
        Apply = { Set-BnqqReg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' 5 }
    },
    @{
        Id = 'usb-suspend-off'; Area = 'Input'; Risk = 'low'; Reboot = $false
        Name = 'Desativar suspensao seletiva USB'
        Apply = { Set-BnqqPowerValue '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' 0 }
    },
    @{
        Id = 'pcie-aspm-off'; Area = 'Latencia'; Risk = 'low'; Reboot = $false
        Name = 'Desativar PCIe ASPM'
        Apply = { Set-BnqqPowerValue '501a4d13-42af-4429-9fd1-a8218c268e20' 'ee12f906-d277-404b-b6da-e5fa1a576df5' 0 }
    },
    @{
        Id = 'core-parking-off'; Area = 'CPU'; Risk = 'low'; Reboot = $false
        Requires = @{ Chassis = 'desktop' }
        Name = 'Desativar core parking'
        Apply = { Set-BnqqCoreParking 100 }
    },
    @{
        Id = 'pagefile-managed'; Area = 'Memoria'; Risk = 'low'; Reboot = $true
        Name = 'Garantir pagefile gerenciado'
        Apply = { Set-BnqqPagefileManaged }
    },
    @{
        Id = 'network-adapter'; Area = 'Rede'; Risk = 'medium'; Reboot = $true
        Name = 'Tunar adaptador de rede'
        Apply = { Set-BnqqNetworkAdapter }
    },
    @{
        Id = 'browser-background-off'; Area = 'Apps'; Risk = 'low'; Reboot = $false
        Name = 'Navegadores: sem background mode'
        Apply = { Set-BnqqBrowserBackground }
    },
    @{
        Id = 'discord-tweaks'; Area = 'Apps'; Risk = 'low'; Reboot = $false
        Name = 'Discord: overlay e aceleracao de hardware off'
        Apply = { Set-BnqqDiscordTweaks }
    },
    @{
        Id = 'startup-trim'; Area = 'Apps'; Risk = 'low'; Reboot = $false
        Name = 'Remover Edge AutoLaunch da inicializacao'
        Apply = { Set-BnqqStartupTrim }
    },
    @{
        Id = 'fast-startup-off'; Area = 'Sistema'; Risk = 'low'; Reboot = $true
        Name = 'Desativar Fast Startup'
        Apply = { Set-BnqqFastStartup -Enabled $false }
    },
    @{
        Id = 'hibernate-off'; Area = 'Sistema'; Risk = 'low'; Reboot = $false
        Requires = @{ Chassis = 'desktop' }
        Name = 'Desativar hibernacao'
        Apply = { Set-BnqqHibernate -Enabled $false }
    },
    @{
        Id = 'memory-compression-off'; Area = 'Memoria'; Risk = 'medium'; Reboot = $true
        Requires = @{ MinRamGB = 16 }
        Name = 'Desativar compressao de memoria'
        Apply = { Set-BnqqMemoryCompression -Enabled $false }
    },
    @{
        Id = 'visual-effects'; Area = 'Sistema'; Risk = 'low'; Reboot = $false
        Name = 'Reduzir efeitos visuais'
        Apply = { Set-BnqqVisualEffects }
    },
    @{
        Id = 'defender-exclusions'; Area = 'Seguranca'; Risk = 'low'; Reboot = $false
        Name = 'Excluir pastas de jogos da varredura'
        Apply = { Set-BnqqDefenderExclusions }
    },
    @{
        Id = 'process-priority'; Area = 'CPU'; Risk = 'low'; Reboot = $false
        Name = 'Prioridade por processo (jogo alto, overlay baixo)'
        Apply = { Set-BnqqProcessPriority }
    },
    @{
        Id = 'services-low'; Area = 'Servicos'; Risk = 'low'; Reboot = $false
        Name = 'Desativar servicos de baixo risco'
        Apply = { Set-BnqqServiceTier -Tier low }
    },
    @{
        Id = 'services-medium'; Area = 'Servicos'; Risk = 'medium'; Reboot = $false
        Name = 'Desativar servicos de medio risco'
        Apply = { Set-BnqqServiceTier -Tier medium }
    },
    @{
        Id = 'timer-defaults'; Area = 'Latencia'; Risk = 'low'; Reboot = $true
        Name = 'Restaurar timer padrao do Windows'
        Apply = { Reset-BnqqTimerDefaults }
    },
    @{
        Id = 'hypervisor-off'; Area = 'Latencia'; Risk = 'high'; Reboot = $true
        Requires = @{ Chassis = 'desktop' }
        Name = 'Desativar Hyper-V no boot'
        Apply = { Set-BnqqHypervisorOff }
    },
    @{
        Id = 'usb-power-off'; Area = 'Input'; Risk = 'low'; Reboot = $true
        Name = 'Desativar suspensao de energia USB/HID'
        Apply = { Set-BnqqUsbPowerSaving }
    },
    @{
        Id = 'usb3-lpm-off'; Area = 'Input'; Risk = 'low'; Reboot = $false
        Name = 'Desativar USB 3 Link Power Management'
        Apply = { Set-BnqqUsb3LinkPowerManagement -Value 0 }
    },
    @{
        Id = 'debloat-appx'; Area = 'Debloat'; Risk = 'medium'; Reboot = $false
        Name = 'Remover apps pre-instalados'
        Apply = { Set-BnqqDebloatAppx }
    },
    @{
        Id = 'tasks-off'; Area = 'Debloat'; Risk = 'low'; Reboot = $false
        Name = 'Desativar tarefas de telemetria e diagnostico'
        Apply = { Set-BnqqScheduledTasks }
    },
    @{
        Id = 'features-off'; Area = 'Debloat'; Risk = 'medium'; Reboot = $true
        Name = 'Desativar recursos opcionais nao usados'
        Apply = { Set-BnqqOptionalFeatures }
    },
    @{
        Id = 'filesystem-tune'; Area = 'Disco'; Risk = 'low'; Reboot = $false
        Name = 'NTFS: sem last access, memory usage 2'
        Apply = { Set-BnqqFilesystem }
    },
    @{
        Id = 'kernel-memory'; Area = 'Memoria'; Risk = 'low'; Reboot = $true
        Name = 'Kernel em RAM e dump reduzido'
        Apply = { Set-BnqqKernelMemory }
    },
    @{
        Id = 'delivery-opt-off'; Area = 'Rede'; Risk = 'low'; Reboot = $false
        Name = 'Delivery Optimization: sem P2P'
        Apply = { Set-BnqqDeliveryOptimization }
    },
    @{
        Id = 'netbios-off'; Area = 'Rede'; Risk = 'low'; Reboot = $false
        Name = 'Desativar NetBIOS sobre TCP/IP'
        Apply = { Set-BnqqNetbiosOff }
    },
    @{
        Id = 'msi-mode'; Area = 'Latencia'; Risk = 'medium'; Reboot = $true
        Name = 'Forcar MSI mode em GPU e rede'
        Apply = { Set-BnqqMsiMode }
    },
    @{
        Id = 'nvidia-max-perf'; Area = 'GPU'; Risk = 'medium'; Reboot = $true
        Requires = @{ Gpu = 'nvidia' }
        Name = 'NVIDIA: performance fixo e telemetria off'
        Apply = { Set-BnqqNvidiaMaxPerf }
    },
    @{
        Id = 'privacy-lockdown'; Area = 'Processos'; Risk = 'low'; Reboot = $false
        Name = 'Desativar Copilot, Recall, widgets e sugestoes'
        Apply = { Set-BnqqPrivacy }
    },
    @{
        Id = 'sleep-policy'; Area = 'Sistema'; Risk = 'low'; Reboot = $false
        Requires = @{ Chassis = 'desktop' }
        Name = 'Desktop nunca suspende nem desliga disco'
        Apply = { Set-BnqqSleepPolicy }
    },
    @{
        Id = 'conditional-services'; Area = 'Servicos'; Risk = 'low'; Reboot = $false
        Name = 'Desativar Spooler/Bluetooth se nao existirem'
        Apply = { Set-BnqqConditionalServices }
    },
    @{
        Id = 'credential-guard-off'; Area = 'Latencia'; Risk = 'medium'; Reboot = $true
        Requires = @{ Chassis = 'desktop' }
        Name = 'Desativar Credential Guard'
        Apply = { Set-BnqqCredentialGuardOff }
    },
    @{
        Id = 'keyboard-response'; Area = 'Input'; Risk = 'low'; Reboot = $false
        Name = 'Teclado: repeat delay 0 e rate maximo'
        Apply = { Set-BnqqKeyboardResponse }
    },
    @{
        Id = 'background-apps-off'; Area = 'Processos'; Risk = 'low'; Reboot = $false
        Name = 'Bloquear apps UWP em segundo plano'
        Apply = { Set-BnqqBackgroundAppsOff }
    },
    @{
        Id = 'fullscreen-opt'; Area = 'Display'; Risk = 'low'; Reboot = $false
        Name = 'Forcar fullscreen exclusivo nos jogos'
        Apply = { Set-BnqqFullscreenOptimizations }
    },
    @{
        Id = 'steam-overlay-off'; Area = 'Apps'; Risk = 'low'; Reboot = $false
        Name = 'Steam: overlay e FPS counter off'
        Apply = { Set-BnqqSteamOverlayOff }
    },
    @{
        Id = 'tcp-tuning'; Area = 'Rede'; Risk = 'low'; Reboot = $false
        Name = 'TCP: ECN e timestamps off, RTO 2000 ms'
        Apply = { Set-BnqqTcpTuning }
    },
    @{
        Id = 'dns-fast'; Area = 'Rede'; Risk = 'low'; Reboot = $false
        Name = 'DNS Cloudflare 1.1.1.1'
        Apply = { Set-BnqqDnsFast }
    },
    @{
        Id = 'reserved-storage-off'; Area = 'Disco'; Risk = 'low'; Reboot = $false
        Name = 'Desativar Reserved Storage'
        Apply = { Set-BnqqReservedStorageOff }
    },
    @{
        Id = 'startup-launchers'; Area = 'Apps'; Risk = 'low'; Reboot = $false
        Name = 'Remover launchers e updaters da inicializacao'
        Apply = { Set-BnqqStartupLaunchers }
    },
    @{
        Id = 'sysmain-off'; Area = 'Servicos'; Risk = 'low'; Reboot = $false
        Requires = @{ Storage = 'hdd' }
        Name = 'Desativar SysMain em disco mecanico'
        Apply = { Set-BnqqServices -Names @('SysMain') }
    },
    @{
        Id = 'gpu-preference'; Area = 'GPU'; Risk = 'low'; Reboot = $false
        Name = 'Fixar jogos na GPU dedicada'
        Apply = { Set-BnqqGpuPreference }
    },
    @{
        Id = 'display-optimizations'; Area = 'Display'; Risk = 'low'; Reboot = $false
        Name = 'VRR e otimizacoes para jogos em janela'
        Apply = { Set-BnqqDisplayOptimizations }
    },
    @{
        Id = 'defender-cpu-limit'; Area = 'Seguranca'; Risk = 'low'; Reboot = $false
        Name = 'Defender: limitar varredura a 20% de CPU'
        Apply = { Set-BnqqDefenderCpuLimit }
    },
    @{
        Id = 'large-system-cache'; Area = 'Memoria'; Risk = 'low'; Reboot = $true
        Requires = @{ MinRamGB = 16 }
        Name = 'LargeSystemCache (16 GB+)'
        Apply = { Set-BnqqLargeSystemCache }
    },
    @{
        Id = 'mitigations-off'; Area = 'CPU'; Risk = 'high'; Reboot = $true
        Requires = @{ Chassis = 'desktop' }
        Name = 'Desativar mitigacoes de CPU (Spectre/Meltdown)'
        Apply = { Set-BnqqMitigationsOff }
    },
    @{
        Id = 'cstates-off'; Area = 'CPU'; Risk = 'medium'; Reboot = $false
        Name = 'Desativar C-states (latencia de wake)'
        Apply = { Set-BnqqCStates -Disabled 1 }
    },
    @{
        Id = 'interrupt-affinity'; Area = 'Latencia'; Risk = 'high'; Reboot = $true
        Requires = @{ Chassis = 'desktop'; MinThreads = 8 }
        Name = 'Afinidade de interrupcao: GPU/NIC/USB fora dos nucleos 0-1'
        Apply = { Set-BnqqInterruptAffinity }
    },
    @{
        Id = 'ndis-offloads'; Area = 'Rede'; Risk = 'medium'; Reboot = $true
        Name = 'NDIS: interrupt moderation, EEE e Green off'
        Apply = { Set-BnqqNdisOffloads }
    },
    @{
        Id = 'rss-tuning'; Area = 'Rede'; Risk = 'medium'; Reboot = $true
        Name = 'RSS: filas de recepcao balanceadas'
        Apply = { Set-BnqqRssTuning }
    },
    @{
        Id = 'tcp-kernel'; Area = 'Rede'; Risk = 'low'; Reboot = $false
        Name = 'TCP kernel: timestamps/ECN off, autotuning normal'
        Apply = { Set-BnqqTcpKernel }
    },
    @{
        Id = 'ntfs-shortnames'; Area = 'Disco'; Risk = 'medium'; Reboot = $true
        Name = 'NTFS: desativar nomes 8.3'
        Apply = { Set-BnqqNtfsShortNames }
    },
    @{
        Id = 'etw-autologgers'; Area = 'Processos'; Risk = 'low'; Reboot = $true
        Name = 'ETW: desativar autologgers de telemetria'
        Apply = { Set-BnqqEtwAutologgers }
    },
    @{
        Id = 'bcd-timer'; Area = 'Latencia'; Risk = 'medium'; Reboot = $true
        Name = 'BCD: TSC forcado e tscsyncpolicy Enhanced'
        Apply = { Set-BnqqBcdTimer }
    },
    @{
        Id = 'browser-choking'; Area = 'Apps'; Risk = 'low'; Reboot = $false
        Name = 'Navegadores: GPU liberada e background timer throttling'
        Apply = { Set-BnqqBrowserChoking }
    },
    @{
        Id = 'shortcut-flags'; Area = 'Apps'; Risk = 'low'; Reboot = $false
        Name = 'Atalhos: flags anti-throttling para Discord/Chromium'
        Apply = { Set-BnqqShortcutFlags }
    },
    @{
        Id = 'ai-cleanup'; Area = 'Processos'; Risk = 'low'; Reboot = $false
        Name = 'IA: Copilot, Recall, Cortana e tarefas de telemetria'
        Apply = { Set-BnqqAiCleanup }
    },
    @{
        Id = 'gpu-vendor-profile'; Area = 'GPU'; Risk = 'medium'; Reboot = $true
        Name = 'GPU: perfil de vendor (NVIDIA P-state / AMD ULPS+Anti-Lag)'
        Requires = @{ Chassis = 'desktop' }
        Apply = { Set-BnqqGpuVendorProfile }
    },
    @{
        Id = 'io-queue-depth'; Area = 'Disco'; Risk = 'low'; Reboot = $true
        Name = 'I/O: worker threads extras para NVMe'
        Requires = @{ Storage = 'ssd' }
        Apply = { Set-BnqqIoQueueDepth }
    },
    @{
        Id = 'ssd-trim'; Area = 'Disco'; Risk = 'low'; Reboot = $false
        Name = 'TRIM forcado em todos os SSDs NTFS'
        Requires = @{ Storage = 'ssd' }
        Apply = { Invoke-BnqqSsdTrim }
    },
    @{
        Id = 'game-watcher'; Area = 'CPU'; Risk = 'low'; Reboot = $false
        Name = 'Watcher: plano Ultimate ao abrir CS2/Valorant'
        Requires = @{ Chassis = 'desktop' }
        Apply = {
            if ($script:BnqqSystem -and $script:BnqqSystem.IsLaptop) { Install-BnqqWatcher -RespectBattery }
            else { Install-BnqqWatcher }
        }
    },
    @{
        Id = 'game-affinity'; Area = 'CPU'; Risk = 'medium'; Reboot = $false
        Name = 'Watcher + afinidade nos nucleos fisicos (sem SMT)'
        Requires = @{ Chassis = 'desktop'; MinThreads = 8 }
        Apply = { Install-BnqqWatcher -PinPhysical }
    }
)

function Get-BnqqCatalog {
    return $script:TweakCatalog
}

function Get-BnqqProfile {
    param([string]$Name, [string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) { return @() }
    $cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

    if (-not ($cfg.profiles.PSObject.Properties.Name -contains $Name)) {
        throw ('Perfil inexistente: {0}' -f $Name)
    }

    return @($cfg.profiles.$Name)
}

function Set-BnqqPowerValue {
    param([string]$Sub, [string]$Setting, [int]$Value)

    $scheme = (powercfg /getactivescheme) -join ' '
    $guid = [regex]::Match($scheme, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value

    powercfg /setacvalueindex $guid $Sub $Setting $Value 2>$null | Out-Null
    powercfg /setdcvalueindex $guid $Sub $Setting $Value 2>$null | Out-Null
    powercfg /setactive $guid 2>$null | Out-Null
}

function Set-BnqqCoreParking {
    param([int]$Percent)

    powercfg -attributes SUB_PROCESSOR 0cc5b647-c1df-4637-891a-dec35c318583 -ATTRIB_HIDE 2>$null | Out-Null
    Set-BnqqPowerValue '54533251-82be-4824-96c1-47b60b740d00' '0cc5b647-c1df-4637-891a-dec35c318583' $Percent
}

function New-BnqqPowerPlan {
    $laptop = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    $source = if ($laptop) { '381b4222-f694-41f0-9685-ff5bb260df2e' } else { '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }
    $name = if ($laptop) { 'BNQQ Balanced' } else { 'BNQQ Gaming' }

    $current = (powercfg /getactivescheme) -join ' '
    $previous = [regex]::Match($current, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
    Set-BnqqMeta 'PowerPlanId' $previous

    $list = (powercfg /list) -join "`n"
    $match = [regex]::Match($list, '(?m)([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s+\(' + [regex]::Escape($name) + '\)')

    if ($match.Success) {
        $guid = $match.Groups[1].Value
    }
    else {
        $dup = (powercfg /duplicatescheme $source) -join ' '
        $guid = [regex]::Match($dup, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
        if (-not $guid) { throw 'Falha ao duplicar o plano de energia' }
        powercfg /changename $guid $name 'Perfil BNQQ' 2>$null | Out-Null
    }

    powercfg -attributes SUB_PROCESSOR 0cc5b647-c1df-4637-891a-dec35c318583 -ATTRIB_HIDE 2>$null | Out-Null
    powercfg -attributes SUB_PROCESSOR be337238-0d82-4146-a960-4f3749d470c7 -ATTRIB_HIDE 2>$null | Out-Null

    $ac = @(
        @('SUB_PROCESSOR', 'PROCTHROTTLEMIN', 100),
        @('SUB_PROCESSOR', 'PROCTHROTTLEMAX', 100),
        @('SUB_PROCESSOR', 'PERFBOOSTMODE', 2),
        @('SUB_PROCESSOR', 'SYSCOOLPOL', 1),
        @('2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226', 0),
        @('501a4d13-42af-4429-9fd1-a8218c268e20', 'ee12f906-d277-404b-b6da-e5fa1a576df5', 0)
    )

    foreach ($s in $ac) {
        powercfg /setacvalueindex $guid $s[0] $s[1] $s[2] 2>$null | Out-Null
    }

    if ($laptop) {
        $dc = @(
            @('SUB_PROCESSOR', 'PROCTHROTTLEMIN', 5),
            @('SUB_PROCESSOR', 'PROCTHROTTLEMAX', 99),
            @('2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226', 1),
            @('501a4d13-42af-4429-9fd1-a8218c268e20', 'ee12f906-d277-404b-b6da-e5fa1a576df5', 2)
        )
        foreach ($s in $dc) {
            powercfg /setdcvalueindex $guid $s[0] $s[1] $s[2] 2>$null | Out-Null
        }
    }
    else {
        foreach ($s in $ac) {
            powercfg /setdcvalueindex $guid $s[0] $s[1] $s[2] 2>$null | Out-Null
        }
        powercfg /setacvalueindex $guid 54533251-82be-4824-96c1-47b60b740d00 0cc5b647-c1df-4637-891a-dec35c318583 100 2>$null | Out-Null
        powercfg /setdcvalueindex $guid 54533251-82be-4824-96c1-47b60b740d00 0cc5b647-c1df-4637-891a-dec35c318583 100 2>$null | Out-Null
    }

    powercfg /setactive $guid 2>$null | Out-Null
    Write-Bnqq ('Plano {0} ativado' -f $name) 'OK'
}

function Set-BnqqPagefileManaged {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if (-not $cs) { return }

    if (-not $cs.AutomaticManagedPagefile) {
        Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction SilentlyContinue
        Write-Bnqq 'Pagefile voltou para gerenciamento automatico' 'OK'
    }
    else {
        Write-Bnqq 'Pagefile ja esta gerenciado pelo sistema' 'INFO'
    }
}

function Set-BnqqServices {
    param([string[]]$Names)

    $store = @{}
    foreach ($name in $Names) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc -or $svc.StartType -eq 'Disabled') { continue }
        $store[$name] = $svc.StartType.ToString()
        try {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
            Write-Bnqq ('Desativado: {0}' -f $name) 'OK'
        }
        catch { }
    }
    if ($store.Count -gt 0) { Set-BnqqMeta 'Services' $store }
}

function Set-BnqqNetworkAdapter {
    $rules = @(
        @{ Key = '*InterruptModeration'; Value = 0 },
        @{ Key = '*EEE'; Value = 0 },
        @{ Key = 'AdvancedEEE'; Value = 0 },
        @{ Key = 'EnableGreenEthernet'; Value = 0 },
        @{ Key = '*WakeOnMagicPacket'; Value = 0 },
        @{ Key = '*WakeOnPattern'; Value = 0 },
        @{ Key = 'S5WakeOnLan'; Value = 0 }
    )

    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $props = @(Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue)
        foreach ($rule in $rules) {
            $prop = $props | Where-Object { $_.RegistryKeyword -eq $rule.Key } | Select-Object -First 1
            if (-not $prop) { continue }
            if ([string]$prop.RegistryValue -eq [string]$rule.Value) { continue }

            Add-BnqqNetAdapterBackup -Adapter $adapter.Name -Keyword $rule.Key -Value $prop.RegistryValue

            try {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $rule.Key -RegistryValue $rule.Value -ErrorAction Stop
                Write-Bnqq ('{0}: {1} -> {2}' -f $adapter.Name, $rule.Key, $rule.Value) 'OK'
            }
            catch { }
        }
    }
}

function Set-BnqqBrowserBackground {
    foreach ($path in @(
        'HKLM:\SOFTWARE\Policies\Google\Chrome',
        'HKLM:\SOFTWARE\Policies\Microsoft\Edge',
        'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
    )) {
        Set-BnqqReg $path 'BackgroundModeEnabled' 0
        Set-BnqqReg $path 'StartupBoostEnabled' 0
    }
    Write-Bnqq 'Navegadores: background mode desativado' 'OK'
}

function Set-BnqqDiscordTweaks {
    $file = Join-Path $env:APPDATA 'discord\settings.json'
    if (-not (Test-Path -LiteralPath $file)) {
        Write-Bnqq 'Discord nao instalado para este usuario' 'INFO'
        return
    }

    if (Get-Process -Name 'Discord' -ErrorAction SilentlyContinue) {
        Write-Bnqq 'Feche o Discord antes de aplicar' 'WARN'
        return
    }

    $backup = '{0}.bnqq.bak' -f $file
    if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $file -Destination $backup -Force }

    try {
        $json = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
        $json | Add-Member -NotePropertyName 'enableHardwareAcceleration' -NotePropertyValue $false -Force
        $json | Add-Member -NotePropertyName 'enableOverlay' -NotePropertyValue $false -Force
        $json | Add-Member -NotePropertyName 'openOnStartup' -NotePropertyValue $false -Force
        $json | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $file -Encoding UTF8
        Write-Bnqq 'Discord: overlay, HW accel e autostart off' 'OK'
    }
    catch {
        Write-Bnqq 'Falha ao editar config do Discord' 'WARN'
    }
}

function Set-BnqqStartupTrim {
    $run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $props = Get-ItemProperty -LiteralPath $run -ErrorAction SilentlyContinue
    if (-not $props) { return }

    foreach ($p in $props.PSObject.Properties) {
        if ($p.Name -notlike 'MicrosoftEdgeAutoLaunch_*') { continue }
        Set-BnqqReg $run $p.Name $null
        Write-Bnqq 'Edge AutoLaunch removido' 'OK'
    }
}

function Set-BnqqFastStartup {
    param([bool]$Enabled = $false)
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' $(if ($Enabled) { 1 } else { 0 })
    Write-Bnqq ('Fast Startup: {0}' -f $(if ($Enabled) { 'on' } else { 'off' })) 'OK'
}

function Set-BnqqHibernate {
    param([bool]$Enabled = $false)
    if ($Enabled) { & powercfg /hibernate on 2>$null | Out-Null } else { & powercfg /hibernate off 2>$null | Out-Null }
    Write-Bnqq ('Hibernacao: {0}' -f $(if ($Enabled) { 'on' } else { 'off' })) 'OK'
}

function Set-BnqqMemoryCompression {
    param([bool]$Enabled = $false)
    try {
        if ($Enabled) { Enable-MMAgent -MemoryCompression -ErrorAction Stop }
        else { Disable-MMAgent -MemoryCompression -ErrorAction Stop }
        Write-Bnqq 'Memory Compression ajustado' 'OK'
    }
    catch {
        Write-Bnqq ('Memory Compression indisponivel: {0}' -f $_.Exception.Message) 'WARN'
    }
}

function Set-BnqqVisualEffects {
    Set-BnqqReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
    Set-BnqqReg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' 'String'
    Set-BnqqReg 'HKCU:\Control Panel\Desktop' 'DragFullWindows' '0' 'String'
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-BnqqReg $adv 'TaskbarAnimations' 0
    Set-BnqqReg $adv 'ListviewAlphaSelect' 0
    Set-BnqqReg $adv 'ListviewShadow' 0
    Set-BnqqReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
    Set-BnqqReg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
    Write-Bnqq 'Efeitos visuais reduzidos' 'OK'
}

function Set-BnqqDefenderExclusions {
    $paths = New-Object System.Collections.Generic.List[string]

    $candidates = @(
        'C:\Riot Games',
        'C:\Program Files\Riot Games',
        'C:\Program Files\Epic Games',
        'C:\Program Files (x86)\Steam\steamapps\common',
        'C:\Program Files\Steam\steamapps\common'
    )

    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
    if ($steam) { $candidates += (Join-Path $steam 'steamapps\common') }

    foreach ($exe in @(Get-BnqqGameExes)) {
        $dir = Split-Path -Parent $exe
        if ($dir -and (Test-Path -LiteralPath $dir)) { $candidates += $dir }
    }

    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { $paths.Add($c) }
    }

    if ($paths.Count -eq 0) {
        Write-Bnqq 'Nenhuma pasta de jogo encontrada' 'INFO'
        return
    }

    $existing = @()
    try { $existing = @((Get-MpPreference -ErrorAction Stop).ExclusionPath) } catch { }

    foreach ($p in $paths) {
        if ($existing -contains $p) { continue }
        try {
            Add-MpPreference -ExclusionPath $p -ErrorAction Stop
            Write-Bnqq ('Excluido: {0}' -f $p) 'OK'
        }
        catch { }
    }
}

function Set-BnqqProcessPriority {
    $map = @{
        'Discord.exe'                 = 5
        'steamwebhelper.exe'          = 5
        'cs2.exe'                     = 3
        'VALORANT-Win64-Shipping.exe' = 3
    }

    $base = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    foreach ($exe in $map.Keys) {
        $path = Join-Path $base ('{0}\PerfOptions' -f $exe)
        Set-BnqqReg $path 'CpuPriorityClass' $map[$exe]
        Set-BnqqReg $path 'IoPriority' $(if ($map[$exe] -eq 3) { 3 } else { 1 })
        Set-BnqqReg $path 'PagePriority' $(if ($map[$exe] -eq 3) { 5 } else { 1 })
    }
    Write-Bnqq 'Prioridade por processo configurada' 'OK'
}

function Set-BnqqHypervisorOff {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao' }
    & bcdedit /set hypervisorlaunchtype off 2>$null | Out-Null
    Write-Bnqq 'Hyper-V desativado no boot' 'OK'
}

function Set-BnqqHypervisorOn {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao' }
    & bcdedit /set hypervisorlaunchtype auto 2>$null | Out-Null
    Write-Bnqq 'Hyper-V reativado no boot' 'OK'
}

function Get-BnqqBcdAudit {
    $out = & bcdedit /enum '{current}' 2>$null
    $text = ($out -join "`n")

    return [pscustomobject]@{
        UsePlatformClock = if ($text -match 'useplatformclock\s+(\w+)') { $Matches[1] } else { 'nao definido' }
        HypervisorLaunch = if ($text -match 'hypervisorlaunchtype\s+(\w+)') { $Matches[1] } else { 'nao definido' }
    }
}

function Show-BnqqBcd {
    $bcd = Get-BnqqBcdAudit

    Write-Host ''
    Write-Host '  BOOT (BCD)' -ForegroundColor Cyan
    if ($bcd.UsePlatformClock -eq 'nao definido' -and $bcd.HypervisorLaunch -eq 'nao definido') {
        Write-Host '    bcdedit exige elevacao para leitura' -ForegroundColor Yellow
        Write-Host ''
        return
    }
    Write-Host ('    useplatformclock   {0}' -f $bcd.UsePlatformClock) -ForegroundColor Gray
    Write-Host ('    hypervisorlaunch   {0}' -f $bcd.HypervisorLaunch) -ForegroundColor Gray
    Write-Host ''
}

function Invoke-BnqqApply {
    param(
        [string]$Profile,
        [string]$ConfigPath,
        [string]$BackupDir,
        [switch]$WhatIf,
        [switch]$SkipRestorePoint,
        $System
    )

    $ids = Get-BnqqProfile -Name $Profile -ConfigPath $ConfigPath
    if ($ids.Count -eq 0) { throw 'Perfil vazio ou configuracao ausente' }

    $catalog = Get-BnqqCatalog
    $selected = @($catalog | Where-Object { $ids -contains $_.Id })
    if ($selected.Count -eq 0) { throw 'Nenhum tweak corresponde ao perfil' }

    $applicable = @($selected | Where-Object { Test-TweakApplicable -Tweak $_ -System $System })
    $skipped = $selected.Count - $applicable.Count

    if (-not $WhatIf -and -not $SkipRestorePoint) {
        New-BnqqRestorePoint | Out-Null
    }

    Write-Bnqq ('Perfil: {0}  |  {1} aplicaveis  |  {2} ignorados por hardware' -f $Profile, $applicable.Count, $skipped) 'STEP'

    $applied = 0
    $failed = 0

    foreach ($tweak in $applicable) {
        if ($WhatIf) {
            Write-Bnqq ('[whatif] {0}' -f $tweak.Name) 'INFO'
            continue
        }

        try {
            & $tweak.Apply
            $applied++
            Write-Bnqq ('{0}  [{1}/{2}]' -f $tweak.Name, $tweak.Area, $tweak.Risk) 'OK'
        }
        catch {
            $failed++
            Write-Bnqq ('FALHOU: {0} -> {1}' -f $tweak.Name, $_.Exception.Message) 'ERR'
        }
    }

    if ($WhatIf) { return }

    $backupFile = Save-BnqqBackup -Directory $BackupDir
    if ($backupFile) { Write-Bnqq ('Backup: {0}' -f $backupFile) 'INFO' }

    $reboot = @($applicable | Where-Object { $_.Reboot }).Count
    Write-Bnqq ('Aplicados: {0}  |  Falhas: {1}  |  Exigem reinicio: {2}' -f $applied, $failed, $reboot) 'STEP'

    if ($reboot -gt 0) {
        Write-Bnqq 'Reinicie para aplicar os ajustes de kernel/driver' 'WARN'
    }
}

function Set-BnqqGpuPreference {
    $base = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    if (-not (Test-Path -LiteralPath $base)) { New-Item -Path $base -Force | Out-Null }

    $paths = @(Get-BnqqGameExes)
    if ($paths.Count -eq 0) {
        Write-Bnqq 'Nenhum executavel de jogo encontrado para preferencia de GPU' 'INFO'
        return
    }

    $added = 0
    foreach ($p in $paths) {
        $existing = $null
        try { $existing = Get-ItemPropertyValue -LiteralPath $base -Name $p -ErrorAction Stop } catch { }

        if ($existing -match 'GpuPreference=2') { continue }

        $value = if ([string]::IsNullOrWhiteSpace($existing)) { 'GpuPreference=2;' }
                 else { ($existing.TrimEnd(';') + ';GpuPreference=2;') }

        Set-BnqqReg $base $p $value 'String'
        $added++
    }

    Write-Bnqq ('{0} jogo(s) fixados na GPU dedicada' -f $added) 'OK'
}

function Set-BnqqDisplayOptimizations {
    $base = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    if (-not (Test-Path -LiteralPath $base)) { New-Item -Path $base -Force | Out-Null }

    $existing = ''
    try { $existing = Get-ItemPropertyValue -LiteralPath $base -Name 'DirectXUserGlobalSettings' -ErrorAction Stop } catch { }

    $map = @{}
    foreach ($part in ($existing -split ';')) {
        if ($part -match '^([^=]+)=(.*)$') { $map[$Matches[1]] = $Matches[2] }
    }

    $map['VRROptimizeEnable'] = '1'
    $map['SwapEffectUpgradeEnable'] = '1'

    $value = (($map.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, $_.Value }) -join ';') + ';'
    Set-BnqqReg $base 'DirectXUserGlobalSettings' $value 'String'

    Write-Bnqq 'VRR e otimizacoes para jogos em janela ativados' 'OK'
}

function Set-BnqqDefenderCpuLimit {
    try {
        Set-MpPreference -ScanAvgCPULoadFactor 20 -ErrorAction Stop
        Write-Bnqq 'Defender: varredura limitada a 20% de CPU' 'OK'
    }
    catch {
        Write-Bnqq ('Defender: nao foi possivel ajustar ({0})' -f $_.Exception.Message) 'WARN'
    }
}

function Set-BnqqLargeSystemCache {
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'LargeSystemCache' 0
    Write-Bnqq 'LargeSystemCache=0: working set de jogos priorizado sobre cache de arquivos' 'OK'
}

function Set-BnqqMitigationsOff {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    Set-BnqqReg $base 'FeatureSettingsOverride' 3
    Set-BnqqReg $base 'FeatureSettingsOverrideMask' 3
    Write-Bnqq 'Mitigacoes de CPU desativadas (requer reboot)' 'OK'
}

function Set-BnqqCStates {
    param([int]$Disabled = 1)

    $scheme = (powercfg /getactivescheme) -join ' '
    $guid = [regex]::Match($scheme, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
    if (-not $guid) { throw 'Plano de energia ativo nao identificado' }

    powercfg /setacvalueindex $guid SUB_PROCESSOR 5d76a2ca-e8c0-402f-a133-2158492d58ad $Disabled 2>$null | Out-Null
    powercfg /setdcvalueindex $guid SUB_PROCESSOR 5d76a2ca-e8c0-402f-a133-2158492d58ad $Disabled 2>$null | Out-Null
    powercfg /setactive $guid 2>$null | Out-Null

    Write-Bnqq ('C-states: {0}' -f $(if ($Disabled) { 'desativados' } else { 'ativos' })) 'OK'
}

function Set-BnqqBrowserChoking {
    $targets = @(
        'HKLM:\SOFTWARE\Policies\Google\Chrome',
        'HKLM:\SOFTWARE\Policies\Microsoft\Edge',
        'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
    )

    foreach ($path in $targets) {
        Set-BnqqReg $path 'HardwareAccelerationModeEnabled' 0
        Set-BnqqReg $path 'BackgroundModeEnabled' 0
        Set-BnqqReg $path 'StartupBoostEnabled' 0
    }

    Write-Bnqq 'Navegadores: GPU liberada (HW accel off) e background mode off' 'OK'
}

function Set-BnqqShortcutFlags {
    $targets = @('chrome.exe', 'msedge.exe', 'brave.exe', 'Discord.exe')
    $flags = '--disable-background-timer-throttling --disable-renderer-backgrounding --disable-software-rasterizer'

    $roots = @(
        [Environment]::GetFolderPath('Desktop'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')
    )

    $shell = New-Object -ComObject WScript.Shell
    $store = @{}
    $changed = 0

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }

        foreach ($lnk in @(Get-ChildItem -LiteralPath $root -Filter '*.lnk' -Recurse -Depth 3 -ErrorAction SilentlyContinue)) {
            try {
                $shortcut = $shell.CreateShortcut($lnk.FullName)
                $targetName = Split-Path -Leaf $shortcut.TargetPath
                if ($targets -notcontains $targetName) { continue }
                if ($shortcut.Arguments -match 'disable-background-timer-throttling') { continue }

                $store[$lnk.FullName] = $shortcut.Arguments
                $shortcut.Arguments = ($shortcut.Arguments + ' ' + $flags).Trim()
                $shortcut.Save()
                $changed++
                Write-Bnqq ('Atalho ajustado: {0}' -f $lnk.Name) 'OK'
            }
            catch {
                Write-Bnqq ('Atalho ignorado: {0}' -f $lnk.Name) 'WARN'
            }
        }
    }

    if ($changed -gt 0) { Set-BnqqMeta 'Shortcuts' $store }
    if ($changed -eq 0) { Write-Bnqq 'Nenhum atalho de navegador/Discord elegivel' 'INFO' }
}

function Restore-BnqqShortcuts {
    param($Store)

    if (-not $Store) { return }

    $shell = New-Object -ComObject WScript.Shell
    foreach ($prop in $Store.PSObject.Properties) {
        if (-not (Test-Path -LiteralPath $prop.Name)) { continue }
        try {
            $shortcut = $shell.CreateShortcut($prop.Name)
            $shortcut.Arguments = $prop.Value
            $shortcut.Save()
            Write-Bnqq ('Atalho restaurado: {0}' -f (Split-Path -Leaf $prop.Name)) 'OK'
        }
        catch {
            Write-Bnqq ('Falha ao restaurar atalho: {0}' -f (Split-Path -Leaf $prop.Name)) 'WARN'
        }
    }
}

function Set-BnqqAiCleanup {
    Set-BnqqReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    Set-BnqqReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
    Set-BnqqReg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-BnqqReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1

    foreach ($pkg in @('Microsoft.549981C3F5F10')) {
        Get-AppxPackage -AllUsers -Name $pkg -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    }

    $patterns = @(
        '\Microsoft\Windows\WindowsAI\*',
        '\Microsoft\Windows\Application Experience\*',
        '\Microsoft\Windows\Customer Experience Improvement Program\*'
    )

    $disabled = 0
    foreach ($pattern in $patterns) {
        foreach ($task in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -like $pattern -and $_.State -ne 'Disabled' })) {
            try {
                Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop | Out-Null
                $disabled++
            }
            catch { }
        }
    }

    Write-Bnqq ('IA/telemetria: Copilot/Recall bloqueados, {0} tarefa(s) desativada(s)' -f $disabled) 'OK'
}
