function Get-BnqqLatencyPowerIndex {
    param([string]$Sub, [string]$Setting)

    $out = powercfg /query SCHEME_CURRENT $Sub $Setting 2>$null
    if (-not $out) { return $null }

    $values = [regex]::Matches(($out -join ' '), '0x([0-9a-fA-F]{1,8})') |
        ForEach-Object { [Convert]::ToInt32($_.Groups[1].Value, 16) }
    if ($values.Count -lt 2) { return $null }

    return [pscustomobject]@{
        AC = $values[$values.Count - 2]
        DC = $values[$values.Count - 1]
    }
}

function Get-BnqqLatencyTcpStatus {
    $rows = @()
    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{0}' -f $adapter.InterfaceGuid
        $props = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue
        $rows += [pscustomobject]@{
            Name = $adapter.Name
            Ack = $props.TcpAckFrequency
            NoDelay = $props.TCPNoDelay
        }
    }
    return @($rows)
}

function Get-BnqqLatencyTuneStatus {
    $mpo = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' -Name OverlayTestMode -ErrorAction SilentlyContinue).OverlayTestMode
    $net = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name NetworkThrottlingIndex, SystemResponsiveness -ErrorAction SilentlyContinue
    $idle = Get-BnqqLatencyPowerIndex '54533251-82be-4824-96c1-47b60b740d00' '5d76a2ca-e8c0-402f-a133-2158492d58ad'
    $coal = Get-BnqqLatencyPowerIndex '2e601130-5351-4d9d-8e04-252966bad054' 'c36f0eb4-2988-4a70-8eee-0884fc2c2433'
    $procir = Get-BnqqLatencyPowerIndex '2e601130-5351-4d9d-8e04-252966bad054' 'c42b79aa-aa3a-484b-a98f-2cf32aa90a28'
    $tcp = Get-BnqqLatencyTcpStatus

    return [pscustomobject]@{
        Mpo = $mpo
        NetworkThrottlingIndex = $net.NetworkThrottlingIndex
        SystemResponsiveness = $net.SystemResponsiveness
        Tcp = $tcp
        IdleDisable = $idle
        IoCoalescingTimeout = $coal
        ProcessorIdleResiliency = $procir
    }
}

function Show-BnqqLatencyTuneStatus {
    param($Status)

    if (-not $Status) { $Status = Get-BnqqLatencyTuneStatus }

    Write-Host ''
    Write-Host '  LATENCIA / PRE-REBOOT' -ForegroundColor Cyan
    $mpoColor = if ($Status.Mpo -eq 5) { 'Green' } else { 'Yellow' }
    Write-Host ('    MPO OverlayTestMode      {0}  [{1}]' -f $Status.Mpo, $(if ($Status.Mpo -eq 5) { 'desativado' } else { 'ativo' })) -ForegroundColor $mpoColor
    Write-Host ('    NetworkThrottlingIndex  {0}' -f $Status.NetworkThrottlingIndex) -ForegroundColor Gray
    Write-Host ('    SystemResponsiveness    {0}' -f $Status.SystemResponsiveness) -ForegroundColor Gray
    foreach ($row in @($Status.Tcp)) {
        Write-Host ('    TCP {0,-18} Ack={1} NoDelay={2}' -f $row.Name, $row.Ack, $row.NoDelay) -ForegroundColor Gray
    }
    if ($Status.IdleDisable) {
        Write-Host ('    Processor Idle Disable  AC={0} DC={1}' -f $Status.IdleDisable.AC, $Status.IdleDisable.DC) -ForegroundColor Gray
    }
    else {
        Write-Host '    Processor Idle Disable  indisponivel' -ForegroundColor Yellow
    }
    if ($Status.IoCoalescingTimeout) {
        Write-Host ('    IO coalescing timeout   AC={0} DC={1} ms' -f $Status.IoCoalescingTimeout.AC, $Status.IoCoalescingTimeout.DC) -ForegroundColor Gray
    }
    else { Write-Host '    IO coalescing timeout   indisponivel/oculto no plano' -ForegroundColor Yellow }
    if ($Status.ProcessorIdleResiliency) {
        Write-Host ('    Idle resiliency timer   AC={0} DC={1} ms' -f $Status.ProcessorIdleResiliency.AC, $Status.ProcessorIdleResiliency.DC) -ForegroundColor Gray
    }
    else { Write-Host '    Idle resiliency timer   indisponivel/oculto no plano' -ForegroundColor Yellow }
    Write-Host '    Nota: TcpAckFrequency/TCPNoDelay afetam TCP; o gameplay do CS2 usa UDP.' -ForegroundColor DarkGray
    Write-Host ''
}

function Set-BnqqLatencyTcp {
    if (-not (Test-BnqqAdmin)) { throw 'Latencia TCP: exige elevacao' }

    $base = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    Set-BnqqReg $base 'NetworkThrottlingIndex' 4294967295 'DWord'
    Set-BnqqReg $base 'SystemResponsiveness' 0 'DWord'

    $changed = 0
    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{0}' -f $adapter.InterfaceGuid
        if (-not (Test-Path -LiteralPath $path)) { continue }
        Set-BnqqReg $path 'TcpAckFrequency' 1 'DWord'
        Set-BnqqReg $path 'TCPNoDelay' 1 'DWord'
        $changed++
        Write-Bnqq ('TCP latencia: Ack/NoDelay em {0}' -f $adapter.Name) 'OK'
    }
    if ($changed -eq 0) { Write-Bnqq 'TCP latencia: nenhuma interface ativa' 'WARN' }
    Write-Bnqq 'TCP latencia: afeta TCP, nao o UDP de gameplay; nao e um tweak de hitreg' 'INFO'
}

function Set-BnqqLatencyPower {
    param([switch]$ForceDeepIdleDisable)

    if (-not (Test-BnqqAdmin)) { throw 'Latencia de energia: exige elevacao' }

    $proc = '54533251-82be-4824-96c1-47b60b740d00'
    $ir = '2e601130-5351-4d9d-8e04-252966bad054'
    $idleDisable = '5d76a2ca-e8c0-402f-a133-2158492d58ad'
    $idleDemote = '4b92d758-5a24-4851-a470-815d78aee119'
    $idlePromote = '7b224883-b3cc-4d79-819f-8374152cbe7c'
    $coalescing = 'c36f0eb4-2988-4a70-8eee-0884fc2c2433'
    $resiliency = 'c42b79aa-aa3a-484b-a98f-2cf32aa90a28'

    & powercfg -attributes $proc $idleDisable -ATTRIB_HIDE 2>$null | Out-Null
    & powercfg -attributes $proc $idleDemote -ATTRIB_HIDE 2>$null | Out-Null
    & powercfg -attributes $proc $idlePromote -ATTRIB_HIDE 2>$null | Out-Null
    & powercfg -attributes $ir $coalescing -ATTRIB_HIDE 2>$null | Out-Null
    & powercfg -attributes $ir $resiliency -ATTRIB_HIDE 2>$null | Out-Null

    $scheme = (powercfg /getactivescheme) -join ' '
    $guid = [regex]::Match($scheme, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
    if (-not $guid) { throw 'Plano de energia ativo nao identificado' }

    if ($ForceDeepIdleDisable) {
        $values = @(
            @($proc, $idleDisable, 1),
            @($proc, $idleDemote, 100),
            @($proc, $idlePromote, 100),
            @($ir, $coalescing, 0),
            @($ir, $resiliency, 0)
        )
    }
    else {
        # Default seguro: nao desliga C-states. Apenas garante que uma aplicacao
        # anterior do modo agressivo nao deixou o plano com IDLEDISABLE=1.
        $values = @(
            @($proc, $idleDisable, 0),
            @($proc, $idleDemote, 40),
            @($proc, $idlePromote, 60),
            @($ir, $coalescing, 0),
            @($ir, $resiliency, 0)
        )
    }
    $failed = 0
    foreach ($v in $values) {
        & powercfg /setacvalueindex $guid $v[0] $v[1] $v[2] 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { $failed++ }
        & powercfg /setdcvalueindex $guid $v[0] $v[1] $v[2] 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { $failed++ }
    }
    & powercfg /setactive $guid 2>$null | Out-Null
    if ($failed -gt 0) {
        Write-Bnqq ('Energia: {0} valor(es) recusado(s); COALTIME/PROCIR podem nao existir neste plano/firmware' -f $failed) 'WARN'
    }
    elseif ($ForceDeepIdleDisable) {
        Write-Bnqq 'Energia AVANCADA: idle disable, demote/promote 100, IO coalescing 0 e resiliency timer 0' 'WARN'
    }
    else {
        Write-Bnqq 'Energia segura: idle enable, demote 40/promote 60; C-states nao foram desativados' 'OK'
    }
    Write-Bnqq 'Energia: C-states efetivos dependem do firmware AMD; o Windows apenas solicita idle disable' 'INFO'
}

function Set-BnqqLatencyTune {
    param(
        [switch]$Remove,
        [switch]$ForceDeepIdleDisable
    )

    if (-not (Test-BnqqAdmin)) { throw 'Latencia: exige elevacao' }
    if (-not $Remove) { Assert-BnqqHeavyQa }

    if ($Remove) {
        Set-BnqqReg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' $null
        $base = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
        Set-BnqqReg $base 'NetworkThrottlingIndex' 10 'DWord'
        Set-BnqqReg $base 'SystemResponsiveness' 20 'DWord'
        foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
            $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{0}' -f $adapter.InterfaceGuid
            Set-BnqqReg $path 'TcpAckFrequency' $null
            Set-BnqqReg $path 'TCPNoDelay' $null
        }
        $proc = '54533251-82be-4824-96c1-47b60b740d00'
        $ir = '2e601130-5351-4d9d-8e04-252966bad054'
        $scheme = (powercfg /getactivescheme) -join ' '
        $guid = [regex]::Match($scheme, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
        if ($guid) {
            foreach ($v in @(
                @($proc, '5d76a2ca-e8c0-402f-a133-2158492d58ad', 0),
                @($proc, '4b92d758-5a24-4851-a470-815d78aee119', 40),
                @($proc, '7b224883-b3cc-4d79-819f-8374152cbe7c', 60),
                @($ir, 'c36f0eb4-2988-4a70-8eee-0884fc2c2433', 0),
                @($ir, 'c42b79aa-aa3a-484b-a98f-2cf32aa90a28', 0)
            )) {
                & powercfg /setacvalueindex $guid $v[0] $v[1] $v[2] 2>$null | Out-Null
                & powercfg /setdcvalueindex $guid $v[0] $v[1] $v[2] 2>$null | Out-Null
            }
            & powercfg /setactive $guid 2>$null | Out-Null
        }
        Write-Bnqq 'Latencia: MPO/TCP removidos e energia voltou aos defaults conservadores' 'OK'
        return
    }

    Set-BnqqReg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' 5 'DWord'
    Write-Bnqq 'MPO: OverlayTestMode=5 (DWM sem multiplane overlay)' 'OK'
    Set-BnqqLatencyTcp
    Set-BnqqLatencyPower -ForceDeepIdleDisable:$ForceDeepIdleDisable
    Write-Bnqq 'Latencia: reboot necessario para MPO e parte do driver de rede' 'WARN'
}
