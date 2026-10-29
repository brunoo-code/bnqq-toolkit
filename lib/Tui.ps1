function Show-BnqqBanner {
    $lines = @(
        '   ____  _   _  ___  ___  ',
        '  | __ )| \ | |/ _ \/ _ \ ',
        '  |  _ \|  \| | | | | | |',
        '  | |_) | |\  | |_| | |_|',
        '  |____/|_| \_|\__\_\\___|',
        '        system engineering'
    )

    Write-Host ''
    foreach ($line in $lines) {
        Write-Host ('  ' + $line) -ForegroundColor Cyan
    }
    Write-Host ('  BNQQ OPTIMIZER v1.3.0  |  {0}  |  {1}' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor DarkGray
    Write-Host ''
}

function Get-BnqqGameInstallStatus {
    $rows = New-Object System.Collections.Generic.List[object]
    $exes = @(Get-BnqqGameExes)

    foreach ($item in @(
        @{ Name = 'Counter-Strike 2'; Pattern = 'cs2.exe' },
        @{ Name = 'VALORANT'; Pattern = 'VALORANT-Win64-Shipping.exe' },
        @{ Name = 'League of Legends'; Pattern = 'League of Legends.exe' }
    )) {
        $hit = $exes | Where-Object { (Split-Path -Leaf $_) -ieq $item.Pattern } | Select-Object -First 1
        $rows.Add([pscustomobject]@{
            Name = $item.Name
            Found = [bool]$hit
            Path = $hit
        })
    }

    return $rows
}

function Get-BnqqBar1MB {
    if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) { return $null }

    try {
        $lines = & nvidia-smi -q 2>$null
        $idx = ($lines | Select-String -Pattern 'BAR1 Memory Usage' | Select-Object -First 1).LineNumber
        if (-not $idx) { return $null }

        $total = $lines[$idx..([math]::Min($idx + 4, $lines.Count - 1))] |
            Select-String -Pattern 'Total\s*:\s*(\d+)' | Select-Object -First 1
        if ($total) { return [int]$total.Matches[0].Groups[1].Value }
    }
    catch { }

    return $null
}

function Get-BnqqAnomalies {
    param($System)

    $list = New-Object System.Collections.Generic.List[object]

    $add = {
        param([string]$Severity, [string]$Title, [string]$Detail)
        $list.Add([pscustomobject]@{ Severity = $Severity; Title = $Title; Detail = $Detail })
    }

    $board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    if ($board -and $System.CpuVendor -eq 'amd' -and $board.Product -match '(H61|B75|B85|H81|Z87|Z97|H110|B150|B250|Z270|Z370|Z390|H310|B360|B365|B460|H410|B560|Z490|Z590|H510|B660|Z690|Z790|H610|X99|X299)') {
        & $add 'CRITICO' 'SMBIOS adulterado' ('Placa reportada: {0} {1}, incompativel com CPU {2}. Nao use esse modelo para BIOS ou drivers de chipset.' -f $board.Manufacturer, $board.Product, $System.CpuName.Trim())
    }

    $bar1 = Get-BnqqBar1MB
    if ($bar1 -and $bar1 -le 1024) {
        & $add 'AVISO' 'Resizable BAR desativado' ('BAR1 atual: {0} MB. Ative Above 4G Decoding e Re-Size BAR no firmware.' -f $bar1)
    }

    if ($System.VbsStatus -eq 2) {
        & $add 'AVISO' 'VBS/HVCI ativo' 'Virtualizacao em syscalls. Em desktop gamer, desative Core Isolation se o anticheat permitir.'
    }

    if ($System.Pagefile -eq 0) {
        & $add 'AVISO' 'Pagefile ausente' 'Anticheats e o proprio Windows podem falhar sem arquivo de paginacao.'
    }

    if ($System.RamSpeed -and $System.RamSpeed -lt 2933) {
        & $add 'AVISO' 'RAM abaixo do esperado' ('{0} MT/s em {1} canal(is). Ative EXPO/DOCP se os modulos suportarem.' -f $System.RamSpeed, $System.RamChannels)
    }

    $pending = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    ) | Where-Object { Test-Path -LiteralPath $_ }

    if ($pending) {
        & $add 'INFO' 'Reinicio pendente' 'Ajustes de driver, MSI e BCD so entram em vigor apos reiniciar.'
    }

    foreach ($game in @(Get-BnqqGameInstallStatus)) {
        if (-not $game.Found) { continue }
        $dir = Split-Path -Parent $game.Path
        if (-not (Test-Path -LiteralPath $dir)) {
            & $add 'CRITICO' ('{0} inconsistente' -f $game.Name) ('Executavel registrado em {0}, mas a pasta nao existe.' -f $game.Path)
        }
    }

    return $list
}

function Invoke-BnqqDeepScan {
    $steps = @(
        'Topologia de CPU',
        'Memoria e canais',
        'GPU e barramento PCIe',
        'MSI e afinidade de interrupcao',
        'Pilha NDIS',
        'Armazenamento e SMART',
        'Servicos ativos',
        'Tarefas agendadas',
        'Boot e timer',
        'Firmware e anomalias'
    )

    $system = $null
    $bcd = $null
    $kernel = @()
    $adapters = @()
    $disks = @()
    $volumes = @()
    $services = 0
    $tasks = 0

    for ($i = 0; $i -lt $steps.Count; $i++) {
        $pct = [int](($i / $steps.Count) * 100)
        Write-Progress -Activity 'BNQQ DEEP SCAN' -Status $steps[$i] -PercentComplete $pct

        switch ($i) {
            0 { $system = Get-SystemInfo }
            1 { @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue) | Out-Null }
            2 {
                if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
                    & nvidia-smi --query-gpu=name,pcie.link.gen.current,pcie.link.width.current,memory.total --format=csv,noheader 2>$null | Out-Null
                }
            }
            3 { $kernel = @(Get-BnqqKernelAudit) }
            4 { $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }) }
            5 {
                $disks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
                $volumes = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })
            }
            6 { $services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' }).Count }
            7 { $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Ready' }).Count }
            8 { $bcd = Get-BnqqBcdAudit }
            9 { }
        }

        Start-Sleep -Milliseconds 90
    }

    Write-Progress -Activity 'BNQQ DEEP SCAN' -Completed

    $anomalies = @(Get-BnqqAnomalies -System $system)
    $games = @(Get-BnqqGameInstallStatus)
    $tier = Get-BnqqTier

    Write-Host ''
    Write-Host '  DEEP SCAN' -ForegroundColor Cyan
    Write-Host ('    Tier         {0}' -f $tier.ToUpper()) -ForegroundColor Gray
    Write-Host ('    CPU          {0}' -f $system.CpuName) -ForegroundColor Gray
    Write-Host ('    Topologia    {0} nucleos / {1} threads' -f $system.Cores, $system.Threads) -ForegroundColor Gray
    Write-Host ('    RAM          {0} GB  {1} MT/s  {2} canal(is)' -f $system.RamGB, $system.RamSpeed, $system.RamChannels) -ForegroundColor Gray
    Write-Host ('    GPU          {0}  driver {1}' -f $system.GpuName, $system.GpuDriver) -ForegroundColor Gray
    Write-Host ('    Display      {0}  {1} Hz' -f $system.Resolution, $system.RefreshRate) -ForegroundColor Gray
    Write-Host ('    Plano        {0}' -f $system.PowerPlan) -ForegroundColor Gray
    Write-Host ('    Servicos     {0} em execucao' -f $services) -ForegroundColor Gray
    Write-Host ('    Tarefas      {0} prontas' -f $tasks) -ForegroundColor Gray

    Write-Host ''
    Write-Host '  INTERRUPCOES' -ForegroundColor Cyan
    if ($kernel.Count -eq 0) {
        Write-Host '    Nenhum dispositivo MSI mapeado' -ForegroundColor DarkGray
    }
    else {
        foreach ($row in $kernel) {
            Write-Host ('    {0,-6} MSI={1}  Prioridade={2}  Policy={3}  Mask={4}' -f $row.Device, $row.Msi, $row.Priority, $row.Policy, $row.Mask) -ForegroundColor Gray
        }
    }

    Write-Host ''
    Write-Host '  REDE' -ForegroundColor Cyan
    foreach ($adapter in $adapters) {
        $props = @(Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue)
        Write-Host ('    {0}  {1}  {2}  ({3} keywords)' -f $adapter.Name, $adapter.LinkSpeed, $adapter.MacAddress, $props.Count) -ForegroundColor Gray
    }

    Write-Host ''
    Write-Host '  ARMAZENAMENTO' -ForegroundColor Cyan
    foreach ($disk in $disks) {
        Write-Host ('    {0}  {1}  {2:N0} GB  {3}' -f $disk.FriendlyName, $disk.MediaType, ($disk.Size / 1GB), $disk.HealthStatus) -ForegroundColor Gray
    }
    foreach ($vol in $volumes) {
        Write-Host ('      {0}: {1}  livre {2:N1} GB de {3:N1} GB' -f $vol.DriveLetter, $vol.FileSystem, ($vol.SizeRemaining / 1GB), ($vol.Size / 1GB)) -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host '  JOGOS' -ForegroundColor Cyan
    foreach ($game in $games) {
        if ($game.Found) {
            Write-Host ('    {0,-18} OK   {1}' -f $game.Name, $game.Path) -ForegroundColor Green
        }
        else {
            Write-Host ('    {0,-18} nao instalado' -f $game.Name) -ForegroundColor DarkGray
        }
    }

    Write-Host ''
    Write-Host '  ANOMALIAS' -ForegroundColor Cyan
    if ($anomalies.Count -eq 0) {
        Write-Host '    Nenhuma anomalia detectada' -ForegroundColor Green
    }
    else {
        foreach ($a in $anomalies) {
            $color = switch ($a.Severity) {
                'CRITICO' { 'Red' }
                'AVISO'   { 'Yellow' }
                default   { 'Gray' }
            }
            Write-Host ('    [{0}] {1}' -f $a.Severity, $a.Title) -ForegroundColor $color
            Write-Host ('           {0}' -f $a.Detail) -ForegroundColor DarkGray
        }
    }

    $pro = Get-BnqqProTierStatus
    Show-BnqqProTierStatus -Status $pro
    if (-not $pro.AllOk -and [Environment]::UserInteractive) {
        $applyPro = Read-Host '  Aplicar Pro-Tier agora? (s/N)'
        if ($applyPro -match '^(s|sim|y|yes)$') {
            & (Join-Path $script:BnqqRoot 'bnqq.ps1') pro -ProTierAction apply
        }
    }

    $god = Get-BnqqGodTierStatus
    Show-BnqqGodTierStatus -Status $god
    $vg = Get-BnqqVanguardStatus
    Show-BnqqVanguardStatus -Status $vg
    Show-BnqqQaStatus

    Write-Host ''
}

function Invoke-BnqqTui {
    Show-BnqqBanner

    while ($true) {
        Write-Host '  [1] Deep Scan' -ForegroundColor White
        Write-Host '  [2] Aplicar perfil' -ForegroundColor White
        Write-Host '  [3] Reverter ultimo apply' -ForegroundColor White
        Write-Host '  [4] Game watcher' -ForegroundColor White
        Write-Host '  [5] Relatorio modular' -ForegroundColor White
        Write-Host '  [6] Veredito (placebo x real)' -ForegroundColor White
        Write-Host '  [7] Estabilidade PBO (WHEA 18/19)' -ForegroundColor White
        Write-Host '  [8] Timer resolution' -ForegroundColor White
        Write-Host '  [9] QoS / DSCP 46' -ForegroundColor White
        Write-Host '  [10] Audio / audiodg' -ForegroundColor White
        Write-Host '  [11] Pro-Tier (rede/energia)' -ForegroundColor White
        Write-Host '  [12] God-Tier (CFG/memória)' -ForegroundColor White
        Write-Host '  [13] Vanguard (IRQ/RSS/standby)' -ForegroundColor White
        Write-Host '  [14] QA: Stress Test In-Game' -ForegroundColor White
        Write-Host '  [15] Ultimate (Super Pack)' -ForegroundColor White
        Write-Host '  [16] ACPI / HPET / TSC' -ForegroundColor White
        Write-Host '  [17] MSI / PCIe' -ForegroundColor White
        Write-Host '  [18] Compensacao VBS / HVCI' -ForegroundColor White
        Write-Host '  [19] Virtual QA C#' -ForegroundColor White
        Write-Host '  [20] HID / USB Runtime' -ForegroundColor White
        Write-Host '  [21] ETW / DPC / DWM' -ForegroundColor White
        Write-Host '  [22] Preflight Seguranca' -ForegroundColor White
        Write-Host '  [0] Sair' -ForegroundColor DarkGray
        Write-Host ''

        $choice = Read-Host '  Escolha'
        Write-Host ''

        switch ($choice) {
            '1' { Invoke-BnqqDeepScan }
            '2' {
                $profile = Read-Host '  Perfil (lowend/laptop/desktop/gaming/fresh/extreme/auto)'
                if ($profile) {
                    & (Join-Path $script:BnqqRoot 'bnqq.ps1') apply -Profile $profile
                }
            }
            '3' {
                & (Join-Path $script:BnqqRoot 'bnqq.ps1') revert
            }
            '4' {
                Show-BnqqWatcherStatus
                Write-Host ''
                Write-Host '  [1] Instalar (sem pin fisico)' -ForegroundColor White
                Write-Host '  [2] Instalar (pin fisico)' -ForegroundColor White
                Write-Host '  [3] Remover' -ForegroundColor White
                Write-Host '  [0] Voltar' -ForegroundColor DarkGray
                $sub = Read-Host '  Escolha'
                switch ($sub) {
                    '1' { & (Join-Path $script:BnqqRoot 'bnqq.ps1') watch -WatcherAction install }
                    '2' { & (Join-Path $script:BnqqRoot 'bnqq.ps1') watch -WatcherAction install -PinPhysical }
                    '3' { & (Join-Path $script:BnqqRoot 'bnqq.ps1') watch -WatcherAction remove }
                }
            }
            '5' {
                & (Join-Path $script:BnqqRoot 'bnqq.ps1') report
            }
            '6' {
                & (Join-Path $script:BnqqRoot 'bnqq.ps1') verdict -Profile all
            }
            '7' {
                & (Join-Path $script:BnqqRoot 'bnqq.ps1') stability
            }
            '8' {
                Show-BnqqTimerStatus
            }
            '9' {
                Show-BnqqQosStatus
            }
            '10' {
                Show-BnqqAudioStatus
            }
            '11' {
                $pro = Get-BnqqProTierStatus
                Show-BnqqProTierStatus -Status $pro
                $sub = Read-Host '  [1] Aplicar [2] Remover [0] Voltar'
                if ($sub -eq '1') { & (Join-Path $script:BnqqRoot 'bnqq.ps1') pro -ProTierAction apply }
                elseif ($sub -eq '2') { & (Join-Path $script:BnqqRoot 'bnqq.ps1') pro -ProTierAction remove }
            }
            '12' {
                $god = Get-BnqqGodTierStatus
                Show-BnqqGodTierStatus -Status $god
                $sub = Read-Host '  [1] Aplicar [2] Remover [0] Voltar'
                if ($sub -eq '1') { & (Join-Path $script:BnqqRoot 'bnqq.ps1') god -GodAction apply }
                elseif ($sub -eq '2') { & (Join-Path $script:BnqqRoot 'bnqq.ps1') god -GodAction remove }
            }
            '13' {
                $vg = Get-BnqqVanguardStatus
                Show-BnqqVanguardStatus -Status $vg
                $sub = Read-Host '  [1] Aplicar [0] Voltar'
                if ($sub -eq '1') { & (Join-Path $script:BnqqRoot 'bnqq.ps1') vanguard -VanguardAction apply }
            }
            '14' { Invoke-BnqqInGameQa -Seconds 45 }
            '15' {
                $ult = Get-BnqqUltimateStatus
                Show-BnqqUltimateStatus -Status $ult
                $sub = Read-Host '  [1] Aplicar [2] Aplicar + AppX [3] Aplicar + VBS off [0] Voltar'
                if ($sub -eq '1') { & (Join-Path $script:BnqqRoot 'bnqq.ps1') ultimate -UltimateAction apply }
                elseif ($sub -eq '2') { & (Join-Path $script:BnqqRoot 'bnqq.ps1') ultimate -UltimateAction apply -RemoveAppx }
                elseif ($sub -eq '3') { & (Join-Path $script:BnqqRoot 'bnqq.ps1') ultimate -UltimateAction apply -VbsOff }
            }
            '16' { Show-BnqqAcpiStatus }
            '17' { Show-BnqqMsiStatus }
            '18' {
                Show-BnqqCompensationStatus
                $sub = Read-Host '  [1] Aplicar compensacao [0] Voltar'
                if ($sub -eq '1') { Set-BnqqCompensation }
            }
            '19' { Invoke-BnqqVirtualQa -Seconds 20 -Ticks 128 }
            '20' {
                Get-BnqqHidRuntimeStatus | Format-List
                $sub = Read-Host '  [1] Aplicar HID [0] Voltar'
                if ($sub -eq '1') { Set-BnqqHidRuntime }
            }
            '21' { Start-BnqqEtwMonitor -Seconds 10 -IntervalMs 500 | Out-Null }
            '22' { Show-BnqqSecurityPreflight }
            '0' { return }
            default { Write-Host '  Opcao invalida' -ForegroundColor Yellow }
        }

        Write-Host ''
        Read-Host '  Enter para continuar' | Out-Null
        Write-Host ''
    }
}
