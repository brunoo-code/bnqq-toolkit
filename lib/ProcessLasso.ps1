function Initialize-BnqqProcessLasso {
    if ('BnqqProcessLasso' -as [type]) { return $true }

    $source = Join-Path $script:BnqqRoot 'lib\BnqqProcessLasso.cs'
    if (-not (Test-Path -LiteralPath $source)) { throw 'BnqqProcessLasso.cs nao encontrado' }

    Add-Type -Path $source -ReferencedAssemblies 'System.Management' -ErrorAction Stop
    return $true
}

$script:BnqqLassoWhitelist = @(
    'System', 'Registry', 'Idle', 'smss', 'csrss', 'wininit', 'winlogon', 'services',
    'lsass', 'svchost', 'fontdrvhost', 'dwm', 'audiodg', 'sihost', 'taskhostw',
    'wmiprvse', 'WmiApSrv', 'TrustedInstaller', 'TiWorker', 'DsmSvc',
    'powershell', 'pwsh', 'WindowsTerminal', 'OpenConsole', 'conhost',
    'RuntimeBroker', 'dllhost', 'GameBar', 'XboxGameBarWidgets',
    'explorer', 'SearchHost', 'StartMenuExperienceHost', 'ShellExperienceHost',
    'TextInputHost', 'ApplicationFrameHost', 'LockApp', 'ctfmon',
    'cs2', 'VALORANT-Win64-Shipping', 'vgc', 'vgk', 'Vanguard', 'vgtray',
    'RiotClientServices', 'RiotClientCrashHandler', 'RiotClientUx',
    'steam', 'steamservice', 'steamwebhelper', 'GameOverlayUI', 'steamerrorreporter',
    'Discord', 'msedge', 'msedgewebview2', 'chrome', 'firefox', 'brave',
    'lghub', 'lghub_agent', 'lghub_updater', 'RazerCentralService', 'RazerSynapse',
    'icue', 'iCUE', 'ArmouryCrate.UserSessionHelper', 'RogLiveService',
    'MsMpEng', 'MsMpEngCP', 'MpDefenderCoreService', 'NisSrv', 'Sense', 'smartscreen',
    'SecurityHealthService', 'SecurityHealthSystray', 'SecurityHealthHost',
    'EasyAntiCheat', 'EasyAntiCheat_EOS', 'BEService', 'BattlEye',
    'NVDisplay.Container', 'nvcontainer', 'nvidia-smi', 'NVIDIA Share',
    'PresentMon', 'CapFrameX', 'RTSS', 'RTSSHooksLoader64',
    'MSIAfterburner', 'RivaTuner64', 'HWiNFO64', 'HWiNFO',
    'obs64', 'obs', 'streamlabs'
)

function Get-BnqqLassoWhitelist {
    return @($script:BnqqLassoWhitelist)
}

function Start-BnqqProcessLasso {
    param(
        [Parameter(Mandatory = $true)][int]$GamePid,
        [int64]$BackgroundMask = 0xAAAA
    )

    if (-not (Test-BnqqAdmin)) {
        Write-Bnqq 'Process Lasso: exige elevacao' 'WARN'
        return $false
    }

    try {
        Initialize-BnqqProcessLasso | Out-Null
        $started = [BnqqProcessLasso]::Start($GamePid, [uint64]$BackgroundMask, [string[]](Get-BnqqLassoWhitelist))
        if ($started) {
            Write-Bnqq ('Process Lasso: WMI Runtime ativo (PID {0}, background 0x{1:X})' -f $GamePid, $BackgroundMask) 'OK'
        }
        else {
            Write-Bnqq 'Process Lasso: WMI Runtime nao iniciou' 'WARN'
        }
        return [bool]$started
    }
    catch {
        Write-Bnqq ('Process Lasso indisponivel: {0}' -f $_.Exception.Message) 'WARN'
        return $false
    }
}

function Stop-BnqqProcessLasso {
    try {
        [BnqqProcessLasso]::Stop()
    }
    catch { }
}

function Get-BnqqProcessLassoStatus {
    $type = 'BnqqProcessLasso' -as [type]
    if (-not $type) {
        return [pscustomobject]@{
            Running = $false
            Tracked = 0
            Actions = 0
            Pending = 0
            Dropped = 0
            GamePid = 0
            Mask = '0xAAAA'
            Last = ''
            Error = 'modulo nao carregado'
        }
    }

    try {
        $text = [BnqqProcessLasso]::Status()
        $data = @{}
        foreach ($part in ($text -split ';')) {
            $pair = $part -split '=', 2
            if ($pair.Count -eq 2) { $data[$pair[0]] = $pair[1] }
        }
        return [pscustomobject]@{
            Running = ($data['running'] -eq '1')
            Tracked = [int]$data['tracked']
            Actions = [int]$data['actions']
            Pending = [int]$data['pending']
            Dropped = [int]$data['dropped']
            GamePid = [int]$data['game_pid']
            Mask = $data['mask']
            Last = $data['last']
            Error = $data['error']
            UptimeSeconds = [int]$data['uptime_s']
        }
    }
    catch {
        return [pscustomobject]@{
            Running = $false
            Tracked = 0
            Actions = 0
            Pending = 0
            Dropped = 0
            GamePid = 0
            Mask = '0xAAAA'
            Last = ''
            Error = $_.Exception.Message
        }
    }
}

function Show-BnqqProcessLassoStatus {
    param($Status)

    if (-not $Status) { $Status = Get-BnqqProcessLassoStatus }
    Write-Host ''
    Write-Host '  PROCESS LASSO / FOREGROUND QUANTUM' -ForegroundColor Cyan
    Write-Host ('    Runtime        {0}  [{1}]' -f $(if ($Status.Running) { 'ativo' } else { 'parado' }), $(if ($Status.Running) { 'WMI eventing' } else { 'aguardando foco' })) -ForegroundColor $(if ($Status.Running) { 'Green' } else { 'Gray' })
    Write-Host ('    Game PID       {0}' -f $Status.GamePid) -ForegroundColor Gray
    Write-Host ('    Background     {0}' -f $Status.Mask) -ForegroundColor Gray
    Write-Host ('    Acoes          {0}  (processos novos rebaixados)' -f $Status.Actions) -ForegroundColor Gray
    Write-Host ('    Rastreados     {0}  pendentes {1}  descartados {2}' -f $Status.Tracked, $Status.Pending, $Status.Dropped) -ForegroundColor Gray
    if ($Status.Last) { Write-Host ('    Ultimo         {0}' -f $Status.Last) -ForegroundColor DarkGray }
    if ($Status.Error) { Write-Host ('    Erro           {0}' -f $Status.Error) -ForegroundColor Yellow }
    Write-Host ''
}

function Get-BnqqForegroundQuantum {
    $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'
    return (Get-ItemProperty -LiteralPath $path -Name Win32PrioritySeparation -ErrorAction SilentlyContinue).Win32PrioritySeparation
}

function Set-BnqqForegroundQuantum {
    param([ValidateSet('balanced', 'max', 'default')][string]$Mode = 'balanced')

    if (-not (Test-BnqqAdmin)) { throw 'Quantum: exige elevacao' }
    $value = switch ($Mode) {
        'max' { 0x2A }
        'default' { 0x02 }
        default { 0x26 }
    }
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' $value 'DWord'
    Write-Bnqq ('Win32PrioritySeparation: 0x{0:X} ({1})' -f $value, $Mode) 'OK'
}
