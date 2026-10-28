$script:ServiceList = @(
    'DiagTrack', 'dmwappushservice', 'MapsBroker', 'RetailDemo', 'wisvc',
    'WMPNetworkSvc', 'Fax', 'PhoneSvc', 'RemoteRegistry', 'WalletService',
    'SDRSVC', 'lfsvc', 'SEMgrSvc', 'WpcMonSvc', 'TrkWks', 'WerSvc',
    'WdiServiceHost', 'WdiSystemHost', 'WbioSrvc', 'SensorService',
    'SensrSvc', 'stisvc', 'NetTcpPortSharing'
)

$script:Catalog = @(
    @{
        Id = 'power-plan'; Area = 'CPU'; Risk = 'low'; Reboot = $false
        Name = 'Plano de energia BNQQ adaptado ao hardware'
        Apply = { New-PowerPlan }
    },
    @{
        Id = 'gamedvr-off'; Area = 'Captura'; Risk = 'low'; Reboot = $false
        Name = 'Desativar Game DVR'
        Apply = {
            Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
        }
    },
    @{
        Id = 'gamemode-on'; Area = 'Latencia'; Risk = 'low'; Reboot = $false
        Name = 'Ativar Game Mode'
        Apply = {
            Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
            Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
            Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'ShowStartupPanel' 0
        }
    },
    @{
        Id = 'power-throttling-off'; Area = 'Latencia'; Risk = 'low'; Reboot = $false
        Name = 'Desativar Power Throttling'
        Apply = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1 }
    },
    @{
        Id = 'mouse-accel-off'; Area = 'Input'; Risk = 'low'; Reboot = $false
        Name = 'Desativar aceleracao do mouse'
        Apply = {
            $base = 'HKCU:\Control Panel\Mouse'
            Set-Reg $base 'MouseSpeed' '0' 'String'
            Set-Reg $base 'MouseThreshold1' '0' 'String'
            Set-Reg $base 'MouseThreshold2' '0' 'String'
            Set-Reg $base 'SmoothMouseXCurve' ([byte[]]@(
                0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
                0x15,0x6E,0x00,0x00,0x00,0x00,0x00,0x00,
                0x00,0x40,0x01,0x00,0x00,0x00,0x00,0x00,
                0x29,0xDC,0x03,0x00,0x00,0x00,0x00,0x00,
                0x00,0x00,0x28,0x00,0x00,0x00,0x00,0x00)) 'Binary'
            Set-Reg $base 'SmoothMouseYCurve' ([byte[]]@(
                0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
                0xFD,0x11,0x00,0x00,0x00,0x00,0x00,0x00,
                0x00,0x24,0x04,0x00,0x00,0x00,0x00,0x00,
                0x00,0x53,0x0A,0x00,0x00,0x00,0x00,0x00,
                0x00,0x00,0x38,0x00,0x00,0x00,0x00,0x00)) 'Binary'
        }
    },
    @{
        Id = 'usb-power-off'; Area = 'Input'; Risk = 'low'; Reboot = $true
        Name = 'Desativar suspensao USB/HID'
        Apply = { Set-UsbPowerSaving }
    },
    @{
        Id = 'usb-suspend-off'; Area = 'Input'; Risk = 'low'; Reboot = $false
        Name = 'Suspensao seletiva USB desligada'
        Apply = { Set-PowerValue '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' 0 }
    },
    @{
        Id = 'pcie-aspm-off'; Area = 'Latencia'; Risk = 'low'; Reboot = $false
        Name = 'Desativar PCIe ASPM'
        Apply = { Set-PowerValue '501a4d13-42af-4429-9fd1-a8218c268e20' 'ee12f906-d277-404b-b6da-e5fa1a576df5' 0 }
    },
    @{
        Id = 'core-parking-off'; Area = 'CPU'; Risk = 'low'; Reboot = $false
        Requires = @{ Chassis = 'desktop' }
        Name = 'Desativar core parking'
        Apply = { Set-CoreParking 100 }
    },
    @{
        Id = 'win32-priority'; Area = 'CPU'; Risk = 'low'; Reboot = $false
        Name = 'Prioridade de foreground'
        Apply = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 26 }
    },
    @{
        Id = 'mmcss-games'; Area = 'CPU'; Risk = 'low'; Reboot = $false
        Name = 'MMCSS categoria Games'
        Apply = {
            $base = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
            Set-Reg $base 'GPU Priority' 8
            Set-Reg $base 'Priority' 6
            Set-Reg $base 'Scheduling Category' 'High' 'String'
            Set-Reg $base 'SFIO Priority' 'High' 'String'
        }
    },
    @{
        Id = 'network-throttling'; Area = 'Rede'; Risk = 'low'; Reboot = $false
        Name = 'Remover throttling de rede multimidia'
        Apply = {
            $base = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            Set-Reg $base 'NetworkThrottlingIndex' 4294967295
            Set-Reg $base 'SystemResponsiveness' 10
        }
    },
    @{
        Id = 'hags-on'; Area = 'GPU'; Risk = 'low'; Reboot = $true
        Requires = @{ MinBuild = 22000 }
        Name = 'Ativar HAGS'
        Apply = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 }
    },
    @{
        Id = 'fse-forced'; Area = 'Display'; Risk = 'low'; Reboot = $false
        Name = 'Fullscreen exclusivo'
        Apply = {
            $base = 'HKCU:\System\GameConfigStore'
            Set-Reg $base 'GameDVR_FSEBehaviorMode' 2
            Set-Reg $base 'GameDVR_HonorUserFSEBehaviorMode' 1
            Set-Reg $base 'GameDVR_DXGIHonorFSEWindowsCompatible' 1
        }
    },
    @{
        Id = 'timer-resolution'; Area = 'Latencia'; Risk = 'low'; Reboot = $true
        Name = 'Permitir timer de 0.5 ms'
        Apply = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1 }
    },
    @{
        Id = 'browser-background-off'; Area = 'Apps'; Risk = 'low'; Reboot = $false
        Name = 'Navegadores sem background mode'
        Apply = { Set-BrowserBackground }
    },
    @{
        Id = 'visual-effects'; Area = 'Sistema'; Risk = 'low'; Reboot = $false
        Name = 'Reduzir efeitos visuais'
        Apply = { Set-VisualEffects }
    },
    @{
        Id = 'fast-startup-off'; Area = 'Sistema'; Risk = 'low'; Reboot = $true
        Name = 'Desativar Fast Startup'
        Apply = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 }
    },
    @{
        Id = 'hibernate-off'; Area = 'Sistema'; Risk = 'low'; Reboot = $false
        Requires = @{ Chassis = 'desktop' }
        Name = 'Desativar hibernacao'
        Apply = { & powercfg /hibernate off 2>$null | Out-Null }
    },
    @{
        Id = 'telemetry-off'; Area = 'Processos'; Risk = 'low'; Reboot = $false
        Name = 'Desativar telemetria'
        Apply = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0 }
    },
    @{
        Id = 'startup-trim'; Area = 'Apps'; Risk = 'low'; Reboot = $false
        Name = 'Remover Edge AutoLaunch da inicializacao'
        Apply = { Set-StartupTrim }
    },
    @{
        Id = 'defender-exclusions'; Area = 'Seguranca'; Risk = 'low'; Reboot = $false
        Name = 'Excluir pastas de jogos da varredura'
        Apply = { Set-DefenderExclusions }
    },
    @{
        Id = 'pagefile-managed'; Area = 'Memoria'; Risk = 'low'; Reboot = $true
        Name = 'Garantir pagefile gerenciado'
        Apply = { Set-PagefileManaged }
    },
    @{
        Id = 'memory-compression-off'; Area = 'Memoria'; Risk = 'medium'; Reboot = $true
        Requires = @{ MinRamGB = 16 }
        Name = 'Desativar compressao de memoria'
        Apply = { Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue }
    },
    @{
        Id = 'hvci-off'; Area = 'Latencia'; Risk = 'medium'; Reboot = $true
        Requires = @{ Chassis = 'desktop' }
        Name = 'Desativar Core Isolation (HVCI)'
        Apply = {
            Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
            Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
        }
    },
    @{
        Id = 'services-low'; Area = 'Servicos'; Risk = 'low'; Reboot = $false
        Name = 'Desativar servicos de baixo risco'
        Apply = { Set-ServiceTier }
    },
    @{
        Id = 'network-adapter'; Area = 'Rede'; Risk = 'medium'; Reboot = $true
        Name = 'Tunar adaptador de rede'
        Apply = { Set-NetworkAdapter }
    }
)

function Get-Catalog { return $script:Catalog }

function Get-ProfileIds {
    param([string]$Name, [string]$ConfigPath)

    $cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not ($cfg.profiles.PSObject.Properties.Name -contains $Name)) { throw "Perfil inexistente: $Name" }
    return @($cfg.profiles.$Name)
}

function Set-PowerValue {
    param([string]$Sub, [string]$Setting, [int]$Value)

    $raw = (powercfg /getactivescheme) -join ' '
    $id = [regex]::Match($raw, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value

    powercfg /setacvalueindex $id $Sub $Setting $Value 2>$null | Out-Null
    powercfg /setdcvalueindex $id $Sub $Setting $Value 2>$null | Out-Null
    powercfg /setactive $id 2>$null | Out-Null
}

function Set-CoreParking {
    param([int]$Percent)

    powercfg -attributes SUB_PROCESSOR 0cc5b647-c1df-4637-891a-dec35c318583 -ATTRIB_HIDE 2>$null | Out-Null
    Set-PowerValue '54533251-82be-4824-96c1-47b60b740d00' '0cc5b647-c1df-4637-891a-dec35c318583' $Percent
}

function New-PowerPlan {
    param([bool]$Laptop = $false)

    $source = if ($Laptop) { '381b4222-f694-41f0-9685-ff5bb260df2e' } else { '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }
    $name = if ($Laptop) { 'BNQQ Balanced' } else { 'BNQQ Gaming' }

    $raw = (powercfg /getactivescheme) -join ' '
    $previous = [regex]::Match($raw, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
    Set-Meta 'PowerPlanId' $previous

    $list = (powercfg /list) -join "`n"
    $found = [regex]::Match($list, '(?m)([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s+\(' + [regex]::Escape($name) + '\)')

    if ($found.Success) {
        $id = $found.Groups[1].Value
    }
    else {
        $dup = (powercfg /duplicatescheme $source) -join ' '
        $id = [regex]::Match($dup, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
        if (-not $id) { throw 'Falha ao duplicar plano de energia' }
        powercfg /changename $id $name 2>$null | Out-Null
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
        powercfg /setacvalueindex $id $s[0] $s[1] $s[2] 2>$null | Out-Null
    }

    if ($Laptop) {
        $dc = @(
            @('SUB_PROCESSOR', 'PROCTHROTTLEMIN', 5),
            @('SUB_PROCESSOR', 'PROCTHROTTLEMAX', 99),
            @('2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226', 1),
            @('501a4d13-42af-4429-9fd1-a8218c268e20', 'ee12f906-d277-404b-b6da-e5fa1a576df5', 2)
        )
        foreach ($s in $dc) {
            powercfg /setdcvalueindex $id $s[0] $s[1] $s[2] 2>$null | Out-Null
        }
    }
    else {
        foreach ($s in $ac) {
            powercfg /setdcvalueindex $id $s[0] $s[1] $s[2] 2>$null | Out-Null
        }
        powercfg /setacvalueindex $id 54533251-82be-4824-96c1-47b60b740d00 0cc5b647-c1df-4637-891a-dec35c318583 100 2>$null | Out-Null
        powercfg /setdcvalueindex $id 54533251-82be-4824-96c1-47b60b740d00 0cc5b647-c1df-4637-891a-dec35c318583 100 2>$null | Out-Null
    }

    powercfg /setactive $id 2>$null | Out-Null
    Write-Log ('Plano {0} ativado' -f $name) 'OK'
}

function Set-PagefileManaged {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($cs -and -not $cs.AutomaticManagedPagefile) {
        Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction SilentlyContinue
        Write-Log 'Pagefile voltou para gerenciamento automatico' 'OK'
    }
}

function Set-UsbPowerSaving {
    $devices = @(Get-PnpDevice -Class USB, HIDClass -Status OK -ErrorAction SilentlyContinue)
    $changed = 0

    foreach ($dev in $devices) {
        if (-not $dev.InstanceId) { continue }
        $path = 'HKLM:\SYSTEM\CurrentControlSet\Enum\{0}\Device Parameters' -f $dev.InstanceId
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $props = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue
        if ($props.EnhancedPowerManagementEnabled -ne $null -and $props.EnhancedPowerManagementEnabled -ne 0) {
            Set-Reg $path 'EnhancedPowerManagementEnabled' 0
            $changed++
        }
        if ($props.AllowIdleIrpInD3 -ne $null -and $props.AllowIdleIrpInD3 -ne 0) {
            Set-Reg $path 'AllowIdleIrpInD3' 0
            $changed++
        }
    }

    Write-Log ('Suspensao USB desativada ({0} ajustes)' -f $changed) 'OK'
}

function Set-BrowserBackground {
    foreach ($path in @(
        'HKLM:\SOFTWARE\Policies\Google\Chrome',
        'HKLM:\SOFTWARE\Policies\Microsoft\Edge',
        'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
    )) {
        Set-Reg $path 'BackgroundModeEnabled' 0
        Set-Reg $path 'StartupBoostEnabled' 0
    }
    Write-Log 'Navegadores: background desativado' 'OK'
}

function Set-VisualEffects {
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
    Set-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' 'String'
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-Reg $adv 'TaskbarAnimations' 0
    Set-Reg $adv 'ListviewAlphaSelect' 0
    Set-Reg $adv 'ListviewShadow' 0
    Write-Log 'Efeitos visuais reduzidos' 'OK'
}

function Set-StartupTrim {
    $run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $props = Get-ItemProperty -LiteralPath $run -ErrorAction SilentlyContinue
    $edge = @($props.PSObject.Properties | Where-Object { $_.Name -like 'MicrosoftEdgeAutoLaunch_*' })
    foreach ($e in $edge) {
        Set-Reg $run $e.Name $null
        Write-Log 'Edge AutoLaunch removido' 'OK'
    }
}

function Set-DefenderExclusions {
    $candidates = @()

    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
    if ($steam) { $candidates += (Join-Path $steam 'steamapps\common') }

    $candidates += @(
        'C:\Riot Games',
        'C:\Program Files\Riot Games',
        'C:\Program Files (x86)\Steam\steamapps\common',
        'C:\Program Files\Epic Games',
        'C:\Program Files (x86)\Ubisoft',
        'C:\Program Files (x86)\Battle.net'
    )

    $existing = @()
    try { $existing = @((Get-MpPreference -ErrorAction Stop).ExclusionPath | Where-Object { $_ -match '^[A-Za-z]:\\' }) } catch { }

    foreach ($c in $candidates) {
        if (-not (Test-Path -LiteralPath $c)) { continue }
        if ($existing -contains $c) { continue }
        try {
            Add-MpPreference -ExclusionPath $c -ErrorAction Stop
            Write-Log ('Excluido: {0}' -f $c) 'OK'
        }
        catch { }
    }
}

function Set-ServiceTier {
    $store = @{}
    foreach ($name in $script:ServiceList) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc -or $svc.StartType -eq 'Disabled') { continue }
        $store[$name] = $svc.StartType.ToString()
        try {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
            Write-Log ('Desativado: {0}' -f $name) 'OK'
        }
        catch { }
    }
    if ($store.Count -gt 0) { Set-Meta 'Services' $store }
}

function Set-NetworkAdapter {
    $rules = @(
        @{ Display = 'Interrupt Moderation'; Value = 'Disabled' },
        @{ Display = 'Energy-Efficient Ethernet'; Value = 'Disabled' },
        @{ Display = 'Green Ethernet'; Value = 'Disabled' },
        @{ Display = 'Flow Control'; Value = 'Disabled' },
        @{ Display = 'Wake on Magic Packet'; Value = 'Disabled' },
        @{ Display = 'Wake on pattern match'; Value = 'Disabled' }
    )

    $store = @{}
    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $props = @(Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue)
        foreach ($rule in $rules) {
            $p = $props | Where-Object { $_.DisplayName -eq $rule.Display } | Select-Object -First 1
            if (-not $p) { continue }
            if ($p.ValidDisplayValues -notcontains $rule.Value) { continue }
            if ($p.DisplayValue -eq $rule.Value) { continue }

            $key = '{0}|{1}' -f $adapter.Name, $p.DisplayName
            $store[$key] = [pscustomobject]@{ Adapter = $adapter.Name; Display = $p.DisplayName; Value = $p.DisplayValue }

            try {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $p.DisplayName -DisplayValue $rule.Value -ErrorAction Stop
                Write-Log ('{0}: {1} -> {2}' -f $adapter.Name, $p.DisplayName, $rule.Value) 'OK'
            }
            catch { }
        }
    }
    if ($store.Count -gt 0) { Set-Meta 'NetAdapter' $store }
}

function Invoke-Optimize {
    param(
        [string]$Profile,
        [string]$ConfigPath,
        [string]$BackupDir,
        [switch]$WhatIf,
        [switch]$NoRestorePoint,
        $System
    )

    $ids = Get-ProfileIds -Name $Profile -ConfigPath $ConfigPath
    $selected = @($script:Catalog | Where-Object { $ids -contains $_.Id })
    $applicable = @($selected | Where-Object { Test-TweakApplicable -Tweak $_ -System $System })

    $skipped = $selected.Count - $applicable.Count

    Write-Step ('Perfil: {0}  |  {1} aplicaveis  |  {2} ignorados por hardware' -f $Profile, $applicable.Count, $skipped)

    if (-not $WhatIf -and -not $NoRestorePoint) { New-RestorePoint | Out-Null }

    $applied = 0
    $failed = 0

    foreach ($tweak in $applicable) {
        if ($WhatIf) {
            Write-Log ('[whatif] {0}' -f $tweak.Name) 'INFO'
            continue
        }
        try {
            if ($tweak.Id -eq 'power-plan') { New-PowerPlan -Laptop $System.IsLaptop }
            else { & $tweak.Apply }
            $applied++
            Write-Log $tweak.Name 'OK'
        }
        catch {
            $failed++
            Write-Log ('FALHOU: {0} -> {1}' -f $tweak.Name, $_.Exception.Message) 'ERR'
        }
    }

    if ($WhatIf) { return }

    $file = Save-Backup -Dir $BackupDir
    if ($file) { Write-Log ('Backup: {0}' -f $file) 'INFO' }

    Write-Step ('Aplicados: {0}  |  Falhas: {1}' -f $applied, $failed)

    if (@($applicable | Where-Object { $_.Reboot }).Count -gt 0) {
        Write-Log 'Reinicie para concluir' 'WARN'
    }
}
