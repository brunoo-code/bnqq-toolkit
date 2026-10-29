function Get-BnqqQaStatus {
    $vanguard = Get-BnqqVanguardStatus
    $timer = Get-BnqqTimerResolution
    $task = Get-ScheduledTask -TaskName 'BNQQ Game Watcher' -ErrorAction SilentlyContinue
    $gameActive = [bool](Get-Process -Name 'cs2', 'VALORANT-Win64-Shipping' -ErrorAction SilentlyContinue)
    $smtMask = Get-BnqqSmtSiblingMask

    $irqOk = ($vanguard.GpuPolicy -eq 4) -and ($vanguard.NicPolicy -eq 4)
    $timerOk = if ($gameActive) { $timer.CurrentMs -le 0.6 } else { $null }
    $watcherOk = ($task -and $task.State -eq 'Running')

    return [pscustomobject]@{
        IrqOk       = $irqOk
        GpuPolicy   = $vanguard.GpuPolicy
        NicPolicy   = $vanguard.NicPolicy
        SmtMask     = ('0x{0:X}' -f $smtMask)
        SmtOk       = ($smtMask -ne 0 -and $watcherOk)
        WatcherOk   = $watcherOk
        GameActive  = $gameActive
        TimerMs     = $timer.CurrentMs
        TimerOk     = $timerOk
        TimerState  = if ($gameActive) { 'jogo ativo' } else { 'idle' }
    }
}

function Show-BnqqQaStatus {
    param($Status)

    if (-not $Status) { $Status = Get-BnqqQaStatus }

    Write-Host ''
    Write-Host '  QA / AMBIENTE' -ForegroundColor Cyan
    Write-Host ('    IRQ GPU      policy {0}  [{1}]' -f $Status.GpuPolicy, $(if ($Status.IrqOk) { 'OK' } else { 'PENDENTE' })) -ForegroundColor $(if ($Status.IrqOk) { 'Green' } else { 'Yellow' })
    Write-Host ('    IRQ rede     policy {0}' -f $Status.NicPolicy) -ForegroundColor $(if ($Status.IrqOk) { 'Green' } else { 'Yellow' })
    Write-Host ('    SMT          {0}  watcher {1}  [{2}]' -f $Status.SmtMask, $(if ($Status.WatcherOk) { 'Running' } else { 'parado' }), $(if ($Status.SmtOk) { 'OK' } else { 'PENDENTE' })) -ForegroundColor $(if ($Status.SmtOk) { 'Green' } else { 'Yellow' })
    $timerText = if ($null -eq $Status.TimerOk) { 'idle: watcher aplica ao abrir o jogo' } elseif ($Status.TimerOk) { 'OK' } else { 'PENDENTE' }
    Write-Host ('    Timer        {0:N3} ms  [{1}]' -f $Status.TimerMs, $timerText) -ForegroundColor $(if ($Status.TimerOk -eq $false) { 'Yellow' } else { 'Gray' })
    Write-Host ''
}
