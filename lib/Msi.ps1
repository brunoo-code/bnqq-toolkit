function Find-BnqqPciDevice {
    param([string]$Pattern)

    $base = 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI'
    foreach ($key in @(Get-ChildItem -LiteralPath $base -Recurse -Depth 3 -ErrorAction SilentlyContinue)) {
        $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        $desc = if ($props.DriverDesc) { $props.DriverDesc } else { $props.DeviceDesc }
        if ($desc -and $desc -match $Pattern) {
            return [pscustomobject]@{ Path = $key.PSPath; Description = $desc; InstanceId = $key.PSChildName }
        }
    }
    return $null
}

function Get-BnqqMsiTargets {
    $layout = Get-BnqqVanguardLayout
    $gpu = Find-BnqqPciDevice -Pattern 'NVIDIA|Radeon|RTX|GTX'
    $nic = Find-BnqqPciDevice -Pattern 'Ethernet|Realtek.*GbE|Intel.*Ethernet'
    return [pscustomobject]@{
        Layout = $layout
        Gpu = $gpu
        Nic = $nic
    }
}

function Set-BnqqMsiTargets {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para configurar MSI' }

    $targets = Get-BnqqMsiTargets
    $map = @(
        @{ Label = 'GPU'; Device = $targets.Gpu; Cpu = $targets.Layout.GpuCpu; Priority = 3 },
        @{ Label = 'Rede'; Device = $targets.Nic; Cpu = $targets.Layout.NicCpu; Priority = 2 }
    )

    foreach ($item in $map) {
        if (-not $item.Device) {
            Write-Bnqq ('MSI: {0} nao localizado na arvore PCI' -f $item.Label) 'WARN'
            continue
        }
        $msiPath = Join-Path $item.Device.Path 'Device Parameters\Interrupt Management\MessageSignaledInterruptProperties'
        $affPath = Join-Path $item.Device.Path 'Device Parameters\Interrupt Management\Affinity Policy'
        Set-BnqqReg $msiPath 'MSISupported' 1 'DWord'
        Set-BnqqReg $msiPath 'DevicePriority' $item.Priority 'DWord'
        Set-BnqqReg $affPath 'DevicePolicy' 4 'DWord'
        Set-BnqqReg $affPath 'AssignmentSetOverride' (New-BnqqAffinityMask -Cpus @($item.Cpu)) 'Binary'
        Write-Bnqq ('MSI: {0} -> 1, prioridade {1}, IRQ CPU {2}' -f $item.Label, $item.Priority, $item.Cpu) 'OK'
    }
}

function Get-BnqqMsiStatus {
    $targets = Get-BnqqMsiTargets
    $rows = @()
    foreach ($item in @(
        @{ Label = 'GPU'; Device = $targets.Gpu },
        @{ Label = 'Rede'; Device = $targets.Nic }
    )) {
        if (-not $item.Device) { continue }
        $msi = Get-ItemProperty -LiteralPath (Join-Path $item.Device.Path 'Device Parameters\Interrupt Management\MessageSignaledInterruptProperties') -ErrorAction SilentlyContinue
        $aff = Get-ItemProperty -LiteralPath (Join-Path $item.Device.Path 'Device Parameters\Interrupt Management\Affinity Policy') -ErrorAction SilentlyContinue
        $mask = if ($aff.AssignmentSetOverride) { (($aff.AssignmentSetOverride | ForEach-Object { $_.ToString('X2') }) -join '') } else { $null }
        $rows += [pscustomobject]@{
            Label = $item.Label
            Device = $item.Device.Description
            Msi = $msi.MSISupported
            Priority = $msi.DevicePriority
            Policy = $aff.DevicePolicy
            Mask = $mask
        }
    }
    return [pscustomobject]@{ Layout = $targets.Layout; Rows = $rows }
}

function Show-BnqqMsiStatus {
    param($Status)
    if (-not $Status) { $Status = Get-BnqqMsiStatus }

    Write-Host ''
    Write-Host '  MSI / PCIe' -ForegroundColor Cyan
    Write-Host ('    Layout       GPU CPU {0} · rede CPU {1}' -f $Status.Layout.GpuCpu, $Status.Layout.NicCpu) -ForegroundColor Gray
    foreach ($row in $Status.Rows) {
        Write-Host ('    {0,-6} MSI={1} prioridade={2} policy={3} mask={4}' -f $row.Label, $row.Msi, $row.Priority, $row.Policy, $row.Mask) -ForegroundColor Gray
        Write-Host ('           {0}' -f $row.Device) -ForegroundColor DarkGray
    }
    Write-Host '    MSI usa interrupcao por mensagem; a mascara e do controlador, nao do USB' -ForegroundColor DarkGray
    Write-Host ''
}
