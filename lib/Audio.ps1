$script:BnqqAudioDefaultCore = 5

function Get-BnqqAudioMask {
    param([int]$Core = $script:BnqqAudioDefaultCore)

    if ($Core -lt 0 -or $Core -gt 63) {
        throw 'Core de audio deve estar entre 0 e 63.'
    }

    return [int64]([int64]1 -shl $Core)
}

function Get-BnqqAudiodgProcess {
    return Get-Process -Name 'audiodg' -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Set-BnqqAudiodgAffinity {
    param(
        [int]$Core = $script:BnqqAudioDefaultCore,
        [switch]$Quiet
    )

    $mask = Get-BnqqAudioMask -Core $Core
    $proc = Get-BnqqAudiodgProcess
    if (-not $proc) {
        return [pscustomobject]@{ Running = $false; Changed = $false; Ok = $false; Mask = $mask; Core = $Core; Error = $null }
    }

    $currentMask = $null
    $currentPriority = $null
    try { $currentMask = [int64]$proc.ProcessorAffinity } catch { }
    try { $currentPriority = $proc.PriorityClass } catch { }

    if ($currentMask -eq $mask -and "$currentPriority" -eq 'High') {
        return [pscustomobject]@{ Running = $true; Changed = $false; Ok = $true; Mask = $mask; Core = $Core; Error = $null }
    }

    try {
        $proc.ProcessorAffinity = [IntPtr]$mask
        $proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
        if (-not $Quiet) {
            Write-Bnqq ('Audio: audiodg PID {0} -> CPU logico {1} (mascara 0x{2:X}) / High' -f $proc.Id, $Core, $mask) 'OK'
        }
        return [pscustomobject]@{ Running = $true; Changed = $true; Ok = $true; Mask = $mask; Core = $Core; Error = $null }
    }
    catch {
        $message = $_.Exception.Message
        if (-not $Quiet) {
            Write-Bnqq ('Audio: audiodg exige elevacao/nao aceitou afinidade: {0}' -f $message) 'WARN'
        }
        return [pscustomobject]@{ Running = $true; Changed = $false; Ok = $false; Mask = $mask; Core = $Core; Error = $message }
    }
}

function Set-BnqqAudioEnhancementsOff {
    Set-BnqqReg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Audio' 'DisableSpatialOnComboEndpoints' 1 'DWord'

    $count = 0
    $property = '{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},7'
    foreach ($kind in @('Render', 'Capture')) {
        $root = Join-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio' $kind
        foreach ($endpoint in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $propsPath = Join-Path $endpoint.PSPath 'Properties'
            if (-not (Test-Path -LiteralPath $propsPath)) { continue }
            Set-BnqqReg $propsPath $property 1 'DWord'
            $count++
        }
    }

    Write-Bnqq ('Audio: spatial off e enhancements desativados em {0} endpoints' -f $count) 'OK'
}

function Get-BnqqAudioTask {
    return Get-ScheduledTask -TaskName 'BNQQ Audio Isolation' -ErrorAction SilentlyContinue
}

function Install-BnqqAudioTask {
    param([int]$Core = $script:BnqqAudioDefaultCore)

    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para instalar a tarefa de audio' }

    $scriptPath = Join-Path $script:BnqqRoot 'bnqq-audio.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath)) { throw 'bnqq-audio.ps1 nao encontrado' }

    $arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Core {1}' -f $scriptPath, $Core
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable

    Stop-ScheduledTask -TaskName 'BNQQ Audio Isolation' -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*bnqq-audio.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500

    Register-ScheduledTask -TaskName 'BNQQ Audio Isolation' -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
    Start-ScheduledTask -TaskName 'BNQQ Audio Isolation' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $task = Get-BnqqAudioTask
    Set-BnqqMeta 'AudioIsolationInstalled' $true
    Set-BnqqMeta 'AudioIsolationCore' $Core
    Write-Bnqq ('Audio: tarefa instalada (CPU logico {0}, estado: {1})' -f $Core, $(if ($task) { $task.State } else { 'ausente' })) 'OK'
}

function Remove-BnqqAudioTask {
    Stop-ScheduledTask -TaskName 'BNQQ Audio Isolation' -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*bnqq-audio.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Unregister-ScheduledTask -TaskName 'BNQQ Audio Isolation' -Confirm:$false -ErrorAction SilentlyContinue

    $proc = Get-BnqqAudiodgProcess
    if ($proc) {
        try {
            $all = [int64]([math]::Pow(2, [Environment]::ProcessorCount) - 1)
            $proc.ProcessorAffinity = [IntPtr]$all
            $proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal
        }
        catch { }
    }

    Set-BnqqMeta 'AudioIsolationInstalled' $false
    Write-Bnqq 'Audio: tarefa removida e audiodg liberado' 'OK'
}

function Set-BnqqAudioIsolation {
    param([int]$Core = $script:BnqqAudioDefaultCore)

    Set-BnqqAudioEnhancementsOff
    Install-BnqqAudioTask -Core $Core
    Set-BnqqAudiodgAffinity -Core $Core | Out-Null
    Write-Bnqq ('Audio: isolamento persistente ativo no CPU logico {0}' -f $Core) 'OK'
}

function Show-BnqqAudioStatus {
    $proc = Get-BnqqAudiodgProcess
    $task = Get-BnqqAudioTask
    $targetCore = $script:BnqqAudioDefaultCore
    if ($task -and $task.Actions.Count -gt 0 -and $task.Actions[0].Arguments -match '-Core\s+(\d+)') {
        $targetCore = [int]$Matches[1]
    }

    Write-Host ''
    Write-Host '  AUDIO / AUDIODG' -ForegroundColor Cyan
    if ($proc) {
        $affinity = 'indisponivel (processo protegido)'
        $priority = 'indisponivel (processo protegido)'
        try {
            $rawAffinity = $proc.ProcessorAffinity
            if ($null -ne $rawAffinity) { $affinity = '0x{0:X}' -f [int64]$rawAffinity }
        }
        catch { }
        try {
            if ($proc.PriorityClass) { $priority = $proc.PriorityClass }
        }
        catch { }
        Write-Host ('    Processo     PID {0}  afinidade {1}  prioridade {2}' -f $proc.Id, $affinity, $priority) -ForegroundColor Gray
    }
    else {
        Write-Host '    Processo     audiodg nao esta em execucao' -ForegroundColor Yellow
    }

    Write-Host ('    Tarefa       {0}' -f $(if ($task) { $task.State } else { 'nao instalada' })) -ForegroundColor Gray
    Write-Host ('    Alvo         CPU logico {0} (mascara 0x{1:X}) / High' -f $targetCore, (Get-BnqqAudioMask -Core $targetCore)) -ForegroundColor Gray
    Write-Host '    Enhancements spatial off; PKEY_AudioEndpoint_Disable_SysFx=1' -ForegroundColor Gray
    Write-Host ''
}
