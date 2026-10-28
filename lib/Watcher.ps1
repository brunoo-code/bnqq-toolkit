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
    Write-Host ''
}

function Install-BnqqWatcher {
    param([switch]$PinPhysical, [switch]$RespectBattery)

    $root = $script:BnqqRoot
    if (-not $root) { throw 'Raiz do projeto nao definida' }

    $script = Join-Path $root 'bnqq-watch.ps1'
    if (-not (Test-Path -LiteralPath $script)) { throw 'bnqq-watch.ps1 nao encontrado' }

    $arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $script
    if ($PinPhysical) { $arguments += ' -PinPhysical' }
    if ($RespectBattery) { $arguments += ' -RespectBattery' }

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable

    Register-ScheduledTask -TaskName 'BNQQ Game Watcher' -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
    Start-ScheduledTask -TaskName 'BNQQ Game Watcher' -ErrorAction SilentlyContinue

    Set-BnqqMeta 'WatcherInstalled' $true
    Set-BnqqMeta 'WatcherPinPhysical' ([bool]$PinPhysical)
    Set-BnqqMeta 'WatcherRespectBattery' ([bool]$RespectBattery)
    Write-Bnqq ('Watcher instalado (pin fisico: {0}, bateria: {1})' -f [bool]$PinPhysical, [bool]$RespectBattery) 'OK'
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
        [switch]$Once
    )

    $games = @('cs2', 'VALORANT-Win64-Shipping')
    $active = $false
    $previousPlan = $null
    $mask = [int64]0
    if ($PinPhysical) { $mask = Get-BnqqPhysicalCoreMask }

    Write-Bnqq ('Watcher iniciado: intervalo {0}s, pin fisico {1}, respeitar bateria {2}' -f $IntervalSeconds, [bool]$PinPhysical, [bool]$RespectBattery) 'STEP'

    while ($true) {
        $running = @(Get-Process -Name $games -ErrorAction SilentlyContinue)

        if ($running.Count -gt 0 -and -not $active) {
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
            }

            if ($PinPhysical -and $mask -ne 0) {
                foreach ($p in $running) { Set-BnqqProcessAffinity -Process $p -Mask $mask }
            }
        }
        elseif ($running.Count -eq 0 -and $active) {
            if ($previousPlan) { & powercfg /setactive $previousPlan 2>$null | Out-Null }
            $active = $false
            Write-Bnqq 'Jogos fechados: plano anterior restaurado' 'OK'
        }

        if ($Once) { break }
        Start-Sleep -Seconds $IntervalSeconds
    }
}
