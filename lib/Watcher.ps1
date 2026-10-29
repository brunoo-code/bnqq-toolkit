function Get-BnqqActivePlanGuid {
    $out = (powercfg /getactivescheme) -join ' '
    $m = [regex]::Match($out, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-BnqqPlanGuidByName {
    param([string]$Name)

    $out = (powercfg /list) -join "`n"
    foreach ($m in [regex]::Matches($out, '(?im)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s*\(([^)]*)\)')) {
        if ($m.Groups[2].Value -match [regex]::Escape($Name)) { return $m.Groups[1].Value }
    }

    return $null
}

function New-BnqqUltimatePlan {
    $guid = Get-BnqqPlanGuidByName -Name 'BNQQ Ultimate'
    if ($guid) { return $guid }

    $out = & powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
    $m = [regex]::Match(($out -join ' '), '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')

    if (-not $m.Success) {
        $out = & powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1
        $m = [regex]::Match(($out -join ' '), '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
    }

    if (-not $m.Success) { throw 'Nao foi possivel criar o plano BNQQ Ultimate' }

    $guid = $m.Groups[1].Value
    & powercfg /changename $guid 'BNQQ Ultimate' 'Ativado pelo watcher durante o jogo' 2>$null | Out-Null
    return $guid
}

function Set-BnqqUltimatePlanValues {
    param([string]$Guid)

    $settings = @(
        @('SUB_PROCESSOR', 'PROCTHROTTLEMIN', 100),
        @('SUB_PROCESSOR', 'PROCTHROTTLEMAX', 100),
        @('SUB_PROCESSOR', 'CPMINCORES', 100),
        @('SUB_PROCESSOR', 'CPMAXCORES', 100),
        @('SUB_PROCESSOR', '5d76a2ca-e8c0-402f-a133-2158492d58ad', 1),
        @('SUB_PROCESSOR', '4b92d758-5a24-4851-a470-815d78aee119', 100),
        @('SUB_PROCESSOR', '7b224883-b3cc-4d79-819f-8374152cbe7c', 100),
        @('2e601130-5351-4d9d-8e04-252966bad054', 'c36f0eb4-2988-4a70-8eee-0884fc2c2433', 0),
        @('2e601130-5351-4d9d-8e04-252966bad054', 'c42b79aa-aa3a-484b-a98f-2cf32aa90a28', 0),
        @('SUB_PROCESSOR', 'PERFBOOSTMODE', 2),
        @('SUB_PROCESSOR', 'PERFBOOSTPOL', 100),
        @('SUB_SLEEP', 'STANDBYIDLE', 0),
        @('SUB_SLEEP', 'HIBERNATEIDLE', 0),
        @('SUB_DISK', 'DISKIDLE', 0),
        @('SUB_PCIEXPRESS', 'ASPM', 0)
    )

    foreach ($s in $settings) {
        & powercfg /setacvalueindex $Guid $s[0] $s[1] $s[2] 2>$null | Out-Null
    }

    & powercfg /setactive $Guid 2>$null | Out-Null
}

function Get-BnqqPhysicalCoreMask {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cpu) { return [int64]0 }

    $logical = [int]$cpu.NumberOfLogicalProcessors
    $cores = [int]$cpu.NumberOfCores
    if ($logical -le 0) { return [int64]0 }
    if ($logical -eq $cores) { return [int64](([int64]1 -shl $logical) - 1) }

    $mask = [int64]0
    for ($i = 0; $i -lt $logical; $i += 2) {
        $mask = $mask -bor ([int64]1 -shl $i)
    }

    return $mask
}

function Get-BnqqSafeGameMask {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cpu) { return [int64]0 }
    $logical = [int]$cpu.NumberOfLogicalProcessors
    $cores = [int]$cpu.NumberOfCores
    if ($logical -le 2) { return [int64]0 }
    if ($cores -gt 0 -and $logical -eq $cores) {
        $mask = [int64]0
        for ($i = 1; $i -lt $logical; $i++) {
            $mask = $mask -bor ([int64]1 -shl $i)
        }
        return $mask
    }

    $mask = [int64]0
    for ($i = 0; $i -lt $logical; $i += 2) {
        $mask = $mask -bor ([int64]1 -shl $i)
    }
    return $mask
}

function Get-BnqqSafeBackgroundMask {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cpu) { return [int64]0 }
    $logical = [int]$cpu.NumberOfLogicalProcessors
    $cores = [int]$cpu.NumberOfCores
    if ($logical -le 3 -or ($cores -gt 0 -and $logical -eq $cores)) { return [int64]0 }

    $mask = [int64]0
    for ($i = 1; $i -lt $logical; $i += 2) {
        $mask = $mask -bor ([int64]1 -shl $i)
    }
    return $mask
}

function Get-BnqqSmtSiblingMask {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cpu) { return [int64]0 }

    $logical = [int]$cpu.NumberOfLogicalProcessors
    if ($logical -le 1) { return [int64]0 }

    $mask = [int64]0
    for ($i = 1; $i -lt $logical; $i += 2) {
        $mask = $mask -bor ([int64]1 -shl $i)
    }

    return $mask
}

function Set-BnqqProcessAffinity {
    param(
        [System.Diagnostics.Process]$Process,
        [int64]$Mask
    )

    try {
        $Process.ProcessorAffinity = [IntPtr]$Mask
        Write-Bnqq ('Afinidade aplicada: {0} -> 0x{1:X}' -f $Process.ProcessName, $Mask) 'OK'
    }
    catch {
        Write-Bnqq ('Afinidade recusada: {0}' -f $Process.ProcessName) 'WARN'
    }
}

function Get-BnqqWatcherTask {
    return Get-ScheduledTask -TaskName 'BNQQ Game Watcher' -ErrorAction SilentlyContinue
}

function Show-BnqqWatcherStatus {
    $task = Get-BnqqWatcherTask
    Write-Host ''
    Write-Host '  GAME WATCHER' -ForegroundColor Cyan

    if (-not $task) {
        Write-Host '    Estado       nao instalado' -ForegroundColor Yellow
    }
    else {
        $info = Get-ScheduledTaskInfo -TaskName 'BNQQ Game Watcher' -ErrorAction SilentlyContinue
        Write-Host ('    Estado       {0}' -f $task.State) -ForegroundColor Green
        Write-Host ('    Ultima run   {0}' -f $info.LastRunTime) -ForegroundColor Gray
        Write-Host ('    Resultado    {0}' -f $info.LastTaskResult) -ForegroundColor Gray
        Write-Host ('    Acao         {0}' -f $task.Actions[0].Arguments) -ForegroundColor DarkGray
    }

    Write-Host ('    Jogo ativo   {0}' -f $(if (Get-Process -Name 'cs2', 'VALORANT-Win64-Shipping' -ErrorAction SilentlyContinue) { 'sim' } else { 'nao' })) -ForegroundColor Gray
    Write-Host ('    Plano atual  {0}' -f (Get-BnqqActivePlanGuid)) -ForegroundColor Gray
    Show-BnqqTimerStatus
    Write-Host ''
}

function Install-BnqqWatcher {
    param([switch]$PinPhysical, [switch]$RespectBattery, [switch]$DeepFreeze)

    $root = $script:BnqqRoot
    if (-not $root) { throw 'Raiz do projeto nao definida' }

    $script = Join-Path $root 'bnqq-watch.ps1'
    if (-not (Test-Path -LiteralPath $script)) { throw 'bnqq-watch.ps1 nao encontrado' }

    $arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $script
    if ($PinPhysical) { $arguments += ' -PinPhysical' }
    if ($RespectBattery) { $arguments += ' -RespectBattery' }
    if ($DeepFreeze) { $arguments += ' -DeepFreeze' }

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable

    Stop-ScheduledTask -TaskName 'BNQQ Game Watcher' -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*bnqq-watch.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500

    Register-ScheduledTask -TaskName 'BNQQ Game Watcher' -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
    Start-ScheduledTask -TaskName 'BNQQ Game Watcher' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $task = Get-BnqqWatcherTask
    if (-not $task -or $task.State -ne 'Running') {
        Start-ScheduledTask -TaskName 'BNQQ Game Watcher' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $task = Get-BnqqWatcherTask
    }

    Set-BnqqMeta 'WatcherInstalled' $true
    Set-BnqqMeta 'WatcherPinPhysical' ([bool]$PinPhysical)
    Set-BnqqMeta 'WatcherRespectBattery' ([bool]$RespectBattery)
    Set-BnqqMeta 'WatcherDeepFreeze' ([bool]$DeepFreeze)
    Write-Bnqq ('Watcher instalado (pin fisico: {0}, bateria: {1}, estado: {2})' -f [bool]$PinPhysical, [bool]$RespectBattery, $(if ($task) { $task.State } else { 'ausente' })) 'OK'
}

function Uninstall-BnqqWatcher {
    $task = Get-BnqqWatcherTask
    if ($task) {
        Unregister-ScheduledTask -TaskName 'BNQQ Game Watcher' -Confirm:$false -ErrorAction SilentlyContinue
        Write-Bnqq 'Tarefa do watcher removida' 'OK'
    }
    else {
        Write-Bnqq 'Watcher nao estava instalado' 'INFO'
    }

    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*bnqq-watch.ps1*' } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            Write-Bnqq ('Processo do watcher encerrado: PID {0}' -f $_.ProcessId) 'OK'
        }

    Set-BnqqMeta 'WatcherInstalled' $false
}

function Start-BnqqWatcher {
    param(
        [int]$IntervalSeconds = 2,
        [switch]$PinPhysical,
        [switch]$RespectBattery,
        [switch]$DeepFreeze,
        [switch]$Once,
        [double]$StandbyThresholdGB = 4
    )

    $games = @('cs2', 'VALORANT-Win64-Shipping')
    $backgroundNames = @('Discord', 'chrome', 'msedge', 'Spotify', 'brave', 'firefox')
    $active = $false
    $previousPlan = $null
    $gpuLocked = $false
    $backgroundPinned = @{}
    $lastStandbyPurge = $null
    $standbyWarned = $false
    $runtimeState = $null
    $runtimePid = $null
    $focusActive = $false
    $focusCandidate = $null
    $focusCandidateSince = $null
    $lassoActive = $false
    $lassoPid = $null
    $lassoWarned = $false
    $mask = [int64]0
    if ($PinPhysical) { $mask = Get-BnqqSafeGameMask }
    $backgroundMask = Get-BnqqSafeBackgroundMask
    $loopInterval = if ($DeepFreeze -and $IntervalSeconds -gt 1) { 1 } else { $IntervalSeconds }

    try { Clear-BnqqGpuClockLock -Quiet | Out-Null } catch { }
    Write-Bnqq ('Watcher iniciado: intervalo {0}s, pin fisico {1}, respeitar bateria {2}' -f $IntervalSeconds, [bool]$PinPhysical, [bool]$RespectBattery) 'STEP'

    try {
        while ($true) {
            $running = @(Get-Process -Name $games -ErrorAction SilentlyContinue)

            if ($running.Count -gt 0) {
                if (-not $active) {
                    $onBattery = $false
                    if ($RespectBattery) {
                        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($battery -and $battery.BatteryStatus -ne 2) { $onBattery = $true }
                    }

                    if ($onBattery) {
                        Write-Bnqq 'Watcher: em bateria, mantendo o plano atual' 'INFO'
                    }
                    else {
                        $previousPlan = Get-BnqqActivePlanGuid
                        $guid = New-BnqqUltimatePlan
                        Set-BnqqUltimatePlanValues -Guid $guid
                        $active = $true
                        Write-Bnqq ('Jogo detectado ({0}) -> BNQQ Ultimate' -f (($running | ForEach-Object { $_.ProcessName }) -join ', ')) 'OK'
                    Set-BnqqDiscordPresence -Game (($running | ForEach-Object { $_.ProcessName }) -join ', ') | Out-Null
                        try { Set-BnqqTimerResolution -Desired 5000 | Out-Null }
                        catch { Write-Bnqq ('Timer resolution indisponivel: {0}' -f $_.Exception.Message) 'WARN' }
                        try {
                            $gpuLocked = Set-BnqqGpuClockLock -Quiet
                            if ($gpuLocked) { Write-Bnqq 'GPU: clock travado no maximo enquanto o jogo estiver ativo' 'OK' }
                        }
                        catch { Write-Bnqq ('GPU state lock indisponivel: {0}' -f $_.Exception.Message) 'WARN' }

                        try {
                            if (Clear-BnqqStandbyList -Quiet) {
                                Write-Bnqq 'Standby list purgada ao detectar o jogo' 'OK'
                            }
                            $lastStandbyPurge = Get-Date
                        }
                        catch {
                            Write-Bnqq ('Standby purge inicial indisponivel: {0}' -f $_.Exception.Message) 'WARN'
                            $standbyWarned = $true
                            $lastStandbyPurge = Get-Date
                        }
                    }
                }

                if ($PinPhysical -and $mask -ne 0) {
                    foreach ($p in $running) { Set-BnqqProcessAffinity -Process $p -Mask $mask }
                }
                foreach ($p in $running) { Set-BnqqGameProcessPriority -Process $p }

                # Repetir a cada ciclo pega abas/processos de background que nasceram depois do jogo.
                if ($backgroundMask -ne 0) {
                    $pinnedNow = 0
                    foreach ($name in $backgroundNames) {
                        foreach ($proc in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
                            if ($backgroundPinned.ContainsKey($proc.Id)) { continue }
                            try {
                                $previousAffinity = $proc.ProcessorAffinity
                                if ($null -eq $previousAffinity) { continue }
                                $proc.ProcessorAffinity = [IntPtr]$backgroundMask
                                $backgroundPinned[$proc.Id] = $previousAffinity
                                $pinnedNow++
                            }
                            catch { }
                        }
                    }
                    if ($pinnedNow -gt 0) {
                        Write-Bnqq ('Background pinado nos threads SMT (0x{0:X}): {1} processo(s)' -f $backgroundMask, $pinnedNow) 'OK'
                    }
                }

                try {
                    $foregroundPid = Get-BnqqForegroundPid
                    $foregroundGame = $running | Where-Object { $_.Id -eq $foregroundPid } | Select-Object -First 1
                    if ($foregroundGame) {
                        if ($focusCandidate -ne $foregroundGame.Id) {
                            $focusCandidate = $foregroundGame.Id
                            $focusCandidateSince = Get-Date
                        }
                        $focusAge = if ($focusCandidateSince) { ((Get-Date) - $focusCandidateSince).TotalSeconds } else { 0 }
                        if ($focusAge -ge 2 -and (-not $focusActive -or $runtimePid -ne $foregroundGame.Id)) {
                            $focusTimer = [Diagnostics.Stopwatch]::StartNew()
                            if ($runtimeState) { Restore-BnqqWorkingSet -State $runtimeState }
                            $runtimePid = $foregroundGame.Id
                            $profile = Get-BnqqGameRuntimeProfile -Process $foregroundGame
                            $runtimeState = Set-BnqqRuntimeLatency -Process $foregroundGame -ExtraMB $profile.WorkingSetExtraMB
                            $frozen = 0
                            if ($DeepFreeze) { $frozen = Freeze-BnqqBackground }
                            $focusTimer.Stop()
                            $focusActive = $true

                            if ($lassoActive -and $lassoPid -ne $foregroundGame.Id) {
                                Stop-BnqqProcessLasso
                                $lassoActive = $false
                                $lassoPid = $null
                            }
                            if (-not $lassoActive -and -not $lassoWarned) {
                                $lassoActive = Start-BnqqProcessLasso -GamePid $foregroundGame.Id -BackgroundMask $backgroundMask
                                if ($lassoActive) { $lassoPid = $foregroundGame.Id }
                                else { $lassoWarned = $true }
                            }

                            Write-Bnqq ('Runtime foco: {0} [{1}] QoS={2} working set={3} freeze={4} lasso={5} E2E={6} ms' -f $foregroundGame.ProcessName, $profile.Game, $runtimeState.QoS, [bool]$runtimeState.WorkingSet, $frozen, [bool]$lassoActive, $focusTimer.ElapsedMilliseconds) 'OK'
                        }
                        if ($DeepFreeze -and $focusActive) { Freeze-BnqqBackground | Out-Null }
                    }
                    elseif ($focusActive) {
                        if ($DeepFreeze) { Resume-BnqqBackground | Out-Null }
                        if ($lassoActive) {
                            Stop-BnqqProcessLasso
                            $lassoActive = $false
                            $lassoPid = $null
                            Write-Bnqq 'Process Lasso: parado e prioridades restauradas' 'OK'
                        }
                        $lassoWarned = $false
                        $focusActive = $false
                        $focusCandidate = $null
                        $focusCandidateSince = $null
                        Write-Bnqq 'Runtime: foco perdido, Deep Freeze liberado' 'OK'
                    }
                    else {
                        $focusCandidate = $null
                        $focusCandidateSince = $null
                    }
                }
                catch {
                    Write-Bnqq ('Runtime foco indisponivel: {0}' -f $_.Exception.Message) 'WARN'
                }

                $freeGB = Get-BnqqFreeMemoryGB
                $now = Get-Date
                $sincePurge = if ($lastStandbyPurge) { ($now - $lastStandbyPurge).TotalSeconds } else { [double]::MaxValue }
                $periodicDue = $focusActive -and $sincePurge -ge 300
                $pressureDue = $focusActive -and ($null -ne $freeGB) -and ($freeGB -lt $StandbyThresholdGB) -and ($sincePurge -ge 60)
                if ($periodicDue -or $pressureDue) {
                    try {
                        if (Clear-BnqqStandbyList -Quiet) {
                            Write-Bnqq ('Standby list purgada ({0})' -f $(if ($pressureDue) { 'pressao de RAM' } else { 'periodica 5 min' })) 'OK'
                        }
                        elseif (-not $standbyWarned) {
                            Write-Bnqq 'Standby purge indisponivel (sem elevacao ou API recusou)' 'WARN'
                            $standbyWarned = $true
                        }
                        $lastStandbyPurge = $now
                    }
                    catch {
                        if (-not $standbyWarned) {
                            Write-Bnqq ('Standby purge indisponivel: {0}' -f $_.Exception.Message) 'WARN'
                            $standbyWarned = $true
                        }
                        $lastStandbyPurge = $now
                    }
                }
            }
            elseif ($active) {
                if ($previousPlan) { & powercfg /setactive $previousPlan 2>$null | Out-Null }
                $active = $false
                try { Clear-BnqqTimerResolution | Out-Null }
                catch { Write-Bnqq ('Timer resolution clear falhou: {0}' -f $_.Exception.Message) 'WARN' }
                if ($DeepFreeze) { Resume-BnqqBackground | Out-Null }
                Clear-BnqqDiscordPresence
                if ($runtimeState) { Restore-BnqqWorkingSet -State $runtimeState; $runtimeState = $null; $runtimePid = $null }
                if ($lassoActive) {
                    Stop-BnqqProcessLasso
                    $lassoActive = $false
                    $lassoPid = $null
                    Write-Bnqq 'Process Lasso: parado (jogo fechado)' 'OK'
                }
                $lassoWarned = $false
                $focusActive = $false
                $focusCandidate = $null
                $focusCandidateSince = $null
                $lastStandbyPurge = $null
                if ($gpuLocked) {
                    try {
                        if (Clear-BnqqGpuClockLock -Quiet) { Write-Bnqq 'GPU: clock liberado (nvidia-smi -rgc)' 'OK' }
                    }
                    catch { Write-Bnqq ('GPU clock clear falhou: {0}' -f $_.Exception.Message) 'WARN' }
                    $gpuLocked = $false
                }
                foreach ($backgroundId in @($backgroundPinned.Keys)) {
                    $proc = Get-Process -Id $backgroundId -ErrorAction SilentlyContinue
                    if (-not $proc) { continue }
                    try { $proc.ProcessorAffinity = [IntPtr]$backgroundPinned[$backgroundId] } catch { }
                }
                $backgroundPinned.Clear()
                Write-Bnqq 'Jogos fechados: plano anterior restaurado' 'OK'
            }

            if ($Once) { break }
            Start-Sleep -Seconds $loopInterval
        }
    }
    finally {
        Clear-BnqqDiscordPresence
        if ($lassoActive) { Stop-BnqqProcessLasso }
        if ($DeepFreeze) { Resume-BnqqBackground | Out-Null }
        if ($runtimeState) { Restore-BnqqWorkingSet -State $runtimeState }
        try { Clear-BnqqTimerResolution | Out-Null } catch { }
        if ($gpuLocked) { try { Clear-BnqqGpuClockLock -Quiet | Out-Null } catch { } }
        foreach ($backgroundId in @($backgroundPinned.Keys)) {
            $proc = Get-Process -Id $backgroundId -ErrorAction SilentlyContinue
            if (-not $proc) { continue }
            try { $proc.ProcessorAffinity = [IntPtr]$backgroundPinned[$backgroundId] } catch { }
        }
        if ($active -and $previousPlan) { & powercfg /setactive $previousPlan 2>$null | Out-Null }
    }
}