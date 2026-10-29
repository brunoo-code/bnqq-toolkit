function Test-BnqqLaptop {
    if (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) { return $true }

    $chassis = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue
    foreach ($type in @($chassis.ChassisTypes)) {
        if ($type -in @(8, 9, 10, 14, 30, 31, 32)) { return $true }
    }

    return $false
}

function Get-BnqqInterruptTargets {
    $targets = [pscustomobject]@{
        Gpu = $null
        Nic = $null
        Usb = $null
    }

    $gpu = Get-PnpDevice -Class Display -Status OK -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -notmatch 'Basic|Remote|Virtual' } |
        Select-Object -First 1
    if ($gpu) { $targets.Gpu = $gpu.InstanceId }

    $nic = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'Up' } |
        Sort-Object ifIndex |
        Select-Object -First 1
    if ($nic) { $targets.Nic = $nic.PnpDeviceID }

    $usb = Get-PnpDevice -Class USB -Status OK -ErrorAction SilentlyContinue |
        Where-Object { $_.Service -eq 'USBXHCI' } |
        Select-Object -First 1
    if ($usb) { $targets.Usb = $usb.InstanceId }

    return $targets
}

function Get-BnqqDeviceKey {
    param(
        [string]$InstanceId,
        [string]$SubKey
    )

    return ('HKLM:\SYSTEM\CurrentControlSet\Enum\{0}\Device Parameters\Interrupt Management\{1}' -f $InstanceId, $SubKey)
}

function New-BnqqAffinityMask {
    param([int[]]$Cpus)

    $bytes = New-Object byte[] 8
    foreach ($cpu in $Cpus) {
        if ($cpu -lt 0 -or $cpu -ge 64) { continue }
        $index = [int][math]::Floor($cpu / 8)
        $bit = $cpu % 8
        $bytes[$index] = $bytes[$index] -bor (1 -shl $bit)
    }

    return , $bytes
}

function Set-BnqqMsiPriority {
    $targets = Get-BnqqInterruptTargets
    $map = @(
        @{ Id = $targets.Gpu; Label = 'GPU'; Priority = 3; Limit = 1 },
        @{ Id = $targets.Nic; Label = 'Rede'; Priority = 2; Limit = 0 },
        @{ Id = $targets.Usb; Label = 'USB'; Priority = 3; Limit = 0 }
    )

    $changed = 0
    foreach ($item in $map) {
        if (-not $item.Id) { continue }

        $path = Get-BnqqDeviceKey $item.Id 'MessageSignaledInterruptProperties'
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Bnqq ('{0}: driver sem MSI' -f $item.Label) 'INFO'
            continue
        }

        Set-BnqqReg $path 'MSISupported' 1
        Set-BnqqReg $path 'DevicePriority' $item.Priority

        if ($item.Limit -gt 0) {
            $current = (Get-ItemProperty -LiteralPath $path -Name MessageNumberLimit -ErrorAction SilentlyContinue).MessageNumberLimit
            if ($null -eq $current) {
                Set-BnqqReg $path 'MessageNumberLimit' $item.Limit
            }
        }

        $changed++
        Write-Bnqq ('{0}: MSI on, DevicePriority {1}' -f $item.Label, $item.Priority) 'OK'
    }

    if ($changed -eq 0) { Write-Bnqq 'Nenhum dispositivo com MSI encontrado' 'WARN' }
}

function Set-BnqqInterruptAffinity {
    if (Test-BnqqLaptop) {
        Write-Bnqq 'Afinidade de interrupcao ignorada em notebook' 'INFO'
        return
    }

    $cpuInfo = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $cpus = [int]$cpuInfo.NumberOfLogicalProcessors

    if ($cpus -lt 8) {
        Write-Bnqq ('Afinidade de interrupcao ignorada: {0} threads (minimo 8)' -f $cpus) 'INFO'
        return
    }

    $groupSize = [math]::Max(1, [math]::Floor(($cpus - 4) / 3))
    $last = $cpus - 1

    $gpuCpus = @(4..([math]::Min(3 + $groupSize, $last)))
    $nicCpus = @((4 + $groupSize)..([math]::Min(3 + 2 * $groupSize, $last)))
    $usbCpus = @((4 + 2 * $groupSize)..([math]::Min(3 + 3 * $groupSize, $last)))

    $targets = Get-BnqqInterruptTargets
    $map = @(
        @{ Id = $targets.Gpu; Label = 'GPU'; Cpus = $gpuCpus },
        @{ Id = $targets.Nic; Label = 'Rede'; Cpus = $nicCpus },
        @{ Id = $targets.Usb; Label = 'USB'; Cpus = $usbCpus }
    )

    foreach ($item in $map) {
        if (-not $item.Id) { continue }

        $path = Get-BnqqDeviceKey $item.Id 'Affinity Policy'
        Set-BnqqReg $path 'DevicePolicy' 4
        Set-BnqqReg $path 'AssignmentSetOverride' (New-BnqqAffinityMask -Cpus $item.Cpus) 'Binary'
        Write-Bnqq ('{0}: interrupcoes nos CPUs {1}' -f $item.Label, ($item.Cpus -join ',')) 'OK'
    }
}

function Add-BnqqNetAdapterBackup {
    param(
        [string]$Adapter,
        [string]$Keyword,
        $Value
    )

    $store = $script:BnqqState.Meta['NetAdapter']
    if (-not $store) { $store = @{} }

    $store[('{0}|{1}' -f $Adapter, $Keyword)] = [pscustomobject]@{
        Adapter = $Adapter
        Keyword = $Keyword
        Value   = $Value
    }

    Set-BnqqMeta 'NetAdapter' $store
}

function Set-BnqqNdisOffloads {
    param([switch]$Aggressive)

    $laptop = Test-BnqqLaptop
    if ($laptop -and $Aggressive) {
        Write-Bnqq 'NDIS agressivo desativado em notebook; aplicando apenas o subconjunto seguro' 'INFO'
        $Aggressive = $false
    }

    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Wi-Fi|Wireless|802\.11|Bluetooth' })

    if ($adapters.Count -eq 0) {
        Write-Bnqq 'Nenhum adaptador Ethernet ativo' 'INFO'
        return
    }

    $rules = @(
        @{ Key = '*InterruptModeration'; Value = 0 },
        @{ Key = '*EEE'; Value = 0 },
        @{ Key = 'AdvancedEEE'; Value = 0 },
        @{ Key = 'EnableGreenEthernet'; Value = 0 },
        @{ Key = '*WakeOnMagicPacket'; Value = 0 },
        @{ Key = '*WakeOnPattern'; Value = 0 },
        @{ Key = 'S5WakeOnLan'; Value = 0 }
    )

    if ($Aggressive) {
        $rules += @(
            @{ Key = '*FlowControl'; Value = 0 },
            @{ Key = '*LsoV2IPv4'; Value = 0 },
            @{ Key = '*LsoV2IPv6'; Value = 0 },
            @{ Key = 'GigaLite'; Value = 0 },
            @{ Key = 'PowerSavingMode'; Value = 0 }
        )
    }

    foreach ($adapter in $adapters) {
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
            catch {
                Write-Bnqq ('{0}: falha em {1}' -f $adapter.Name, $rule.Key) 'WARN'
            }
        }
    }
}

function Set-BnqqRssTuning {
    $cpuInfo = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $cpus = [int]$cpuInfo.NumberOfLogicalProcessors
    $done = 0

    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $prop = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue |
            Where-Object { $_.RegistryKeyword -eq '*RSS' } |
            Select-Object -First 1

        if (-not $prop) { continue }

        if ([string]$prop.RegistryValue -ne '1') {
            Add-BnqqNetAdapterBackup -Adapter $adapter.Name -Keyword '*RSS' -Value $prop.RegistryValue
            try {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword '*RSS' -RegistryValue 1 -ErrorAction Stop
            }
            catch {
                Write-Bnqq ('{0}: RSS nao aceitou ativacao' -f $adapter.Name) 'WARN'
                continue
            }
        }

        $done++

        if ($cpus -ge 8 -and -not (Test-BnqqLaptop)) {
            $base = 4
            $max = [math]::Min(4, $cpus - $base)
            try {
                Set-NetAdapterRss -Name $adapter.Name -BaseProcessorNumber $base -MaxProcessors $max -ErrorAction Stop
                Write-Bnqq ('{0}: RSS base {1}, max {2}' -f $adapter.Name, $base, $max) 'OK'
            }
            catch {
                Write-Bnqq ('{0}: RSS ativo, ajuste de filas nao suportado' -f $adapter.Name) 'INFO'
            }
        }
        else {
            Write-Bnqq ('{0}: RSS ativo (filas mantidas)' -f $adapter.Name) 'OK'
        }
    }

    if ($done -eq 0) { Write-Bnqq 'Nenhum adaptador expoe RSS' 'INFO' }
}

function Set-BnqqTcpKernel {
    $applied = 0
    $total = 0

    foreach ($pair in @(
        @('timestamps', 'disabled'),
        @('ecncapability', 'disabled'),
        @('autotuninglevel', 'normal')
    )) {
        $total++
        & netsh int tcp set global ('{0}={1}' -f $pair[0], $pair[1]) 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $applied++ }
    }

    & netsh int tcp set global congestionprovider=ctcp 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Bnqq 'CTCP indisponivel neste build; mantendo CUBIC' 'INFO'
    }
    else {
        Write-Bnqq 'Congestion provider: CTCP' 'OK'
    }

    & netsh int tcp set global dca=enabled 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Bnqq 'DCA nao suportado neste build' 'INFO' }

    & netsh int tcp set global netdma=enabled 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Bnqq 'NetDMA nao suportado neste build' 'INFO' }

    Write-Bnqq ('TCP global: {0}/{1} aplicados' -f $applied, $total) 'OK'
}

function Set-BnqqNtfsShortNames {
    & fsutil behavior set disable8dot3 1 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Bnqq 'NTFS: nomes 8.3 desativados para novos arquivos' 'OK'
    }
    else {
        Write-Bnqq 'NTFS: falha ao desativar nomes 8.3' 'WARN'
    }
}

function Set-BnqqEtwAutologgers {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger'

    $keys = @()
    try { $keys = @(Get-ChildItem -LiteralPath $base -ErrorAction Stop) } catch { $keys = @() }

    if ($keys.Count -eq 0) {
        Write-Bnqq 'Autologger: sem acesso ou nenhuma sessao presente' 'INFO'
        return
    }

    $disabled = 0
    foreach ($key in $keys) {
        if ($key.PSChildName -notmatch 'DiagTrack|DeviceCensus|CEIP|AutoLogger-Diagtrack') { continue }

        Set-BnqqReg $key.PSPath 'Start' 0
        $disabled++
        Write-Bnqq ('Autologger desativado: {0}' -f $key.PSChildName) 'OK'
    }

    if ($disabled -eq 0) { Write-Bnqq 'Nenhum autologger de telemetria presente' 'INFO' }
}

function Set-BnqqBcdTimer {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao' }

    & bcdedit /set useplatformclock No 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Bnqq 'useplatformclock=No (TSC)' 'OK' }
    else { Write-Bnqq 'useplatformclock: falha' 'WARN' }

    & bcdedit /set tscsyncpolicy Enhanced 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Bnqq 'tscsyncpolicy=Enhanced' 'OK' }
    else { Write-Bnqq 'tscsyncpolicy: falha' 'WARN' }
}

function Set-BnqqBcdDynamicTick {
    param([bool]$Disable = $true)

    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao' }

    if ($Disable) {
        & bcdedit /set disabledynamictick Yes 2>$null | Out-Null
        $label = 'Yes'
    }
    else {
        & bcdedit /deletevalue disabledynamictick 2>$null | Out-Null
        $label = 'removido'
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Bnqq ('disabledynamictick={0} (Pro-Tier opt-in; nao entra no perfil extreme)' -f $label) 'OK'
    }
    else {
        Write-Bnqq 'disabledynamictick: falha' 'WARN'
    }
}

function Get-BnqqKernelAudit {
    $targets = Get-BnqqInterruptTargets
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($item in @(
        @{ Label = 'GPU'; Id = $targets.Gpu },
        @{ Label = 'Rede'; Id = $targets.Nic },
        @{ Label = 'USB'; Id = $targets.Usb }
    )) {
        if (-not $item.Id) { continue }

        $msiPath = Get-BnqqDeviceKey $item.Id 'MessageSignaledInterruptProperties'
        $affPath = Get-BnqqDeviceKey $item.Id 'Affinity Policy'

        $msi = Get-ItemProperty -LiteralPath $msiPath -ErrorAction SilentlyContinue
        $aff = Get-ItemProperty -LiteralPath $affPath -ErrorAction SilentlyContinue

        $mask = ''
        if ($aff.AssignmentSetOverride) {
            $mask = ($aff.AssignmentSetOverride | ForEach-Object { $_.ToString('X2') }) -join ''
        }

        $rows.Add([pscustomobject]@{
            Device   = $item.Label
            Msi      = $msi.MSISupported
            Priority = $msi.DevicePriority
            Policy   = $aff.DevicePolicy
            Mask     = $mask
        })
    }

    return $rows
}

function Show-BnqqKernelAudit {
    $rows = @(Get-BnqqKernelAudit)
    if ($rows.Count -eq 0) { return }

    Write-Host ''
    Write-Host '  INTERRUPCOES (MSI / AFINIDADE)' -ForegroundColor Cyan
    foreach ($row in $rows) {
        Write-Host ('    {0,-6} MSI={1}  Prioridade={2}  Policy={3}  Mask={4}' -f $row.Device, $row.Msi, $row.Priority, $row.Policy, $row.Mask) -ForegroundColor Gray
    }
}
