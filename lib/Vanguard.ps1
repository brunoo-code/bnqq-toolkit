function Get-BnqqVanguardLayout {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $logical = if ($cpu) { [int]$cpu.NumberOfLogicalProcessors } else { [Environment]::ProcessorCount }

    if ($logical -ge 8) {
        $gpuCpu = 4
        $audioCpu = 5
        $nicCpu = 6
    }
    elseif ($logical -ge 4) {
        $gpuCpu = 2
        $audioCpu = 1
        $nicCpu = 3
    }
    else {
        $gpuCpu = 1
        $audioCpu = 0
        $nicCpu = [math]::Max(0, $logical - 1)
    }

    return [pscustomobject]@{
        Logical  = $logical
        GpuCpu   = $gpuCpu
        AudioCpu = $audioCpu
        NicCpu   = $nicCpu
        GpuMask  = ([int64]1 -shl $gpuCpu)
        NicMask  = ([int64]1 -shl $nicCpu)
    }
}

function Set-BnqqVanguardIrqAffinity {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para afinidade de IRQ' }

    $layout = Get-BnqqVanguardLayout
    $targets = Get-BnqqInterruptTargets
    $map = @(
        @{ Label = 'GPU'; Id = $targets.Gpu; Cpu = $layout.GpuCpu; Priority = 3 },
        @{ Label = 'Rede'; Id = $targets.Nic; Cpu = $layout.NicCpu; Priority = 2 }
    )

    foreach ($item in $map) {
        if (-not $item.Id) {
            Write-Bnqq ('{0}: dispositivo nao localizado' -f $item.Label) 'WARN'
            continue
        }

        $msiPath = Get-BnqqDeviceKey $item.Id 'MessageSignaledInterruptProperties'
        $affPath = Get-BnqqDeviceKey $item.Id 'Affinity Policy'
        Set-BnqqReg $msiPath 'DevicePriority' $item.Priority 'DWord'
        Set-BnqqReg $affPath 'DevicePolicy' 4 'DWord'
        Set-BnqqReg $affPath 'AssignmentSetOverride' (New-BnqqAffinityMask -Cpus @($item.Cpu)) 'Binary'
        Write-Bnqq ('{0}: IRQ -> CPU logico {1} (0x{2:X}), prioridade {3}' -f $item.Label, $item.Cpu, ([int64]1 -shl $item.Cpu), $item.Priority) 'OK'
    }
}

function Set-BnqqVanguardRssPinning {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para RSS pinning' }

    $layout = Get-BnqqVanguardLayout
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
    $done = 0
    foreach ($adapter in $adapters) {
        try {
            Set-NetAdapterRss -Name $adapter.Name -BaseProcessorNumber $layout.NicCpu -MaxProcessors 1 -ErrorAction Stop
            Write-Bnqq ('RSS: {0} -> CPU logico {1}' -f $adapter.Name, $layout.NicCpu) 'OK'
            $done++
        }
        catch {
            Write-Bnqq ('RSS: {0} nao aceitou base/max ({1})' -f $adapter.Name, $_.Exception.Message) 'INFO'
        }
    }

    if ($done -eq 0) { Write-Bnqq 'RSS pinning indisponivel neste driver/adaptador' 'WARN' }
}

function Set-BnqqVanguardDisplay {
    Set-BnqqDisplayOptimizations
    Set-BnqqFullscreenOptimizations
    Write-Bnqq 'DXGI: SwapEffectUpgradeEnable=1 e FSO por jogo verificados' 'OK'
}

function Get-BnqqVanguardStatus {
    $layout = Get-BnqqVanguardLayout
    $targets = Get-BnqqInterruptTargets
    $gpuAff = $null
    $nicAff = $null
    if ($targets.Gpu) {
        $gpuAff = Get-ItemProperty -LiteralPath (Get-BnqqDeviceKey $targets.Gpu 'Affinity Policy') -ErrorAction SilentlyContinue
    }
    if ($targets.Nic) {
        $nicAff = Get-ItemProperty -LiteralPath (Get-BnqqDeviceKey $targets.Nic 'Affinity Policy') -ErrorAction SilentlyContinue
    }

    $dx = ''
    try { $dx = Get-ItemPropertyValue -LiteralPath 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -Name 'DirectXUserGlobalSettings' -ErrorAction Stop } catch { }
    $swap = [bool]($dx -match 'SwapEffectUpgradeEnable=1')

    $rss = @(Get-NetAdapterRss -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'vEthernet|Loopback' })
    $rssOk = $null
    if ($rss.Count -gt 0) {
        $rssOk = [bool]($rss | Where-Object { $_.Enabled -and $_.MaxProcessors -eq 1 })
    }

    return [pscustomobject]@{
        Layout = $layout
        GpuPolicy = if ($gpuAff) { $gpuAff.DevicePolicy } else { $null }
        NicPolicy = if ($nicAff) { $nicAff.DevicePolicy } else { $null }
        GpuPriority = if ($gpuAff) { (Get-ItemProperty -LiteralPath (Get-BnqqDeviceKey $targets.Gpu 'MessageSignaledInterruptProperties') -ErrorAction SilentlyContinue).DevicePriority } else { $null }
        SwapEffect = $swap
        RssSupported = ($rss.Count -gt 0)
        RssOk = $rssOk
        FreeGB = Get-BnqqFreeMemoryGB
        TimerCoalescing = 'sem controle suportado no Windows'
        NvidiaDirect = 'driver profile / NVIDIA App; sem chave de registro suportada'
    }
}

function Show-BnqqVanguardStatus {
    param($Status)

    if (-not $Status) { $Status = Get-BnqqVanguardStatus }

    Write-Host ''
    Write-Host '  VANGUARD / IRQ E REDE' -ForegroundColor Cyan
    Write-Host ('    Layout       GPU CPU {0} · audio CPU {1} · rede CPU {2}' -f $Status.Layout.GpuCpu, $Status.Layout.AudioCpu, $Status.Layout.NicCpu) -ForegroundColor Gray
    $gpuColor = if ($Status.GpuPolicy -eq 4) { 'Green' } else { 'Yellow' }
    $nicColor = if ($Status.NicPolicy -eq 4) { 'Green' } else { 'Yellow' }
    Write-Host ('    IRQ GPU      policy {0} · prioridade {1}' -f $Status.GpuPolicy, $Status.GpuPriority) -ForegroundColor $gpuColor
    Write-Host ('    IRQ rede     policy {0}' -f $Status.NicPolicy) -ForegroundColor $nicColor
    Write-Host ('    DXGI swap    SwapEffectUpgrade={0}' -f $Status.SwapEffect) -ForegroundColor $(if ($Status.SwapEffect) { 'Green' } else { 'Yellow' })
    if (-not $Status.RssSupported) {
        Write-Host '    RSS          adaptador/driver sem RSS exposto' -ForegroundColor Yellow
    }
    else {
        Write-Host ('    RSS          {0}' -f $(if ($Status.RssOk) { 'pinned' } else { 'nao pinned' })) -ForegroundColor $(if ($Status.RssOk) { 'Green' } else { 'Yellow' })
    }
    Write-Host ('    Standby      {0} GB livres; purga no watcher ao detectar e a cada 5 min' -f $Status.FreeGB) -ForegroundColor Gray
    Write-Host ('    Timer coalescing  {0}' -f $Status.TimerCoalescing) -ForegroundColor DarkGray
    Write-Host ('    NVIDIA direto     {0}' -f $Status.NvidiaDirect) -ForegroundColor DarkGray
    Write-Host ''
}

function Set-BnqqVanguard {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para aplicar o Vanguard' }

    Set-BnqqVanguardIrqAffinity
    Set-BnqqVanguardRssPinning
    Set-BnqqVanguardDisplay
    Set-BnqqPremiumNetworkOffloads
    Set-BnqqPremiumPowerSettings
    Set-BnqqMeta 'VanguardApplied' $true
    Write-Bnqq 'Vanguard: IRQ, RSS (se suportado), DXGI/FSO, offloads e power preparados' 'OK'
}
