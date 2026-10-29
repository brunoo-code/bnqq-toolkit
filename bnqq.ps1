[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('scan', 'report', 'verdict', 'apply', 'revert', 'status', 'focus', 'unfocus', 'trim', 'rebalance', 'stress', 'stability', 'timer', 'qos', 'audio', 'guide', 'debloat', 'cache', 'bench', 'bcd', 'watch', 'menu', 'help')]
    [string]$Command = 'menu',

    [string]$Profile = 'auto',
    [string]$BackupFile,
    [int]$StabilityMinutes = 5,
    [int]$StabilitySeconds = 0,
    [int]$StabilityThreads = 0,
    [ValidateSet('status', 'install', 'remove', 'run')]
    [string]$WatcherAction = 'status',
    [ValidateSet('status', 'install', 'remove')]
    [string]$AudioAction = 'status',
    [int]$AudioCore = 5,
    [switch]$PinPhysical,
    [switch]$WhatIf,
    [switch]$SkipRestorePoint,
    [switch]$NoElevate
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:BnqqRoot = $root

if ($Command -eq 'menu' -and -not [Environment]::UserInteractive) {
    $Command = 'scan'
}

. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\Kernel.ps1')
. (Join-Path $root 'lib\Detect.ps1')
. (Join-Path $root 'lib\Tweaks.ps1')
. (Join-Path $root 'lib\Services.ps1')
. (Join-Path $root 'lib\Debloat.ps1')
. (Join-Path $root 'lib\Tuning.ps1')
. (Join-Path $root 'lib\Modules.ps1')
. (Join-Path $root 'lib\Verdict.ps1')
. (Join-Path $root 'lib\Boost.ps1')
. (Join-Path $root 'lib\Peripherals.ps1')
. (Join-Path $root 'lib\Gpu.ps1')
. (Join-Path $root 'lib\Storage.ps1')
. (Join-Path $root 'lib\Timer.ps1')
. (Join-Path $root 'lib\Stability.ps1')
. (Join-Path $root 'lib\Qos.ps1')
. (Join-Path $root 'lib\Audio.ps1')
. (Join-Path $root 'lib\Watcher.ps1')
. (Join-Path $root 'lib\Tui.ps1')

$configPath = Join-Path $root 'config\profiles.json'
$reportDir = Join-Path $root 'reports'
$backupDir = Join-Path $root 'backups'
$script:FocusStateFile = Join-Path $backupDir 'focus-state.json'

$needsAdmin = $Command -in @('apply', 'revert', 'debloat', 'focus', 'unfocus', 'rebalance', 'trim')
if ($Command -eq 'watch' -and $WatcherAction -in @('install', 'remove')) { $needsAdmin = $true }
if ($Command -eq 'audio' -and $AudioAction -in @('install', 'remove')) { $needsAdmin = $true }

if ($needsAdmin -and -not (Test-BnqqAdmin) -and -not $NoElevate) {
    $forward = @($Command)
    if ($Command -eq 'apply') {
        $forward += @('-Profile', $Profile)
        if ($WhatIf) { $forward += '-WhatIf' }
        if ($SkipRestorePoint) { $forward += '-SkipRestorePoint' }
    }
    if ($Command -eq 'revert' -and $BackupFile) { $forward += @('-BackupFile', $BackupFile) }
    if ($Command -eq 'watch') {
        $forward += @('-WatcherAction', $WatcherAction)
        if ($PinPhysical) { $forward += '-PinPhysical' }
    }
    if ($Command -eq 'audio') {
        $forward += @('-AudioAction', $AudioAction, '-AudioCore', $AudioCore)
    }
    Invoke-BnqqElevation -ScriptPath $MyInvocation.MyCommand.Path -ScriptArgs $forward
    return
}

Start-BnqqLog -Directory $reportDir | Out-Null

$system = Get-SystemInfo
$script:BnqqSystem = $system
$tier = Get-BnqqTier

if ($Profile -eq 'auto') {
    if ($system.IsLaptop) { $Profile = 'laptop' }
    elseif ($tier -eq 'low') { $Profile = 'lowend' }
    else { $Profile = 'gaming' }
}

function Show-BnqqStatus {
    param($System, [string]$Tier)

    $plan = (powercfg /getactivescheme 2>$null) -join ' '
    $planName = [regex]::Match($plan, '\(([^)]+)\)').Groups[1].Value

    $vbs = 'desconhecido'
    if ($null -ne $System.VbsStatus) {
        $vbs = switch ([int]$System.VbsStatus) {
            0 { 'off' }
            1 { 'configurado, nao ativo' }
            2 { 'ATIVO' }
            default { 'desconhecido' }
        }
    }

    Write-Host ''
    Write-Host '  STATUS' -ForegroundColor Cyan
    Write-Host ('    Tier            {0}' -f $Tier.ToUpper()) -ForegroundColor Gray
    Write-Host ('    CPU             {0}' -f $System.CpuName) -ForegroundColor Gray
    Write-Host ('    GPU             {0}' -f $System.GpuName) -ForegroundColor Gray
    Write-Host ('    RAM             {0} GB @ {1} MT/s' -f $System.RamGB, $System.RamSpeed) -ForegroundColor Gray
    Write-Host ('    Plano           {0}' -f $planName) -ForegroundColor Gray
    Write-Host ('    VBS / HVCI      {0}' -f $vbs) -ForegroundColor $(if ($vbs -eq 'ATIVO') { 'Yellow' } else { 'Green' })
    Write-Host ('    Game DVR        {0}' -f $(if ($System.GameDvr -eq 0) { 'off' } else { 'on' })) -ForegroundColor Gray
    Write-Host ('    HAGS            {0}' -f $(if ($System.Hags -eq 2) { 'on' } else { 'off' })) -ForegroundColor Gray
    if ($System.RefreshRate) {
        Write-Host ('    Display         {0} Hz' -f $System.RefreshRate) -ForegroundColor Gray
    }
    Write-Host ''
}

switch ($Command) {
    'scan' {
        $findings = Get-Findings -System $system
        Show-Scan -System $system -Findings $findings

        Write-Host ('  TIER      {0}  |  perfil sugerido: {1}' -f $tier.ToUpper(), $Profile) -ForegroundColor Cyan
        Write-Host ('  Aplicar:  .\bnqq.ps1 apply -Profile {0}' -f $Profile) -ForegroundColor DarkGray
        Write-Host ''
    }

    'report' {
        $r = Invoke-BnqqModules
        Show-BnqqModules -Report $r
        Show-BnqqKernelAudit
        if (-not (Test-Path -LiteralPath $reportDir)) { New-Item -ItemType Directory -Force -Path $reportDir | Out-Null }
        $out = Join-Path $reportDir ('modules-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $r | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $out -Encoding UTF8
        Write-Bnqq ('Relatorio: {0}' -f $out) 'OK'
    }

    'verdict' {
        if ($Profile -eq 'all' -or -not $PSBoundParameters.ContainsKey('Profile')) { Show-BnqqVerdicts -ConfigPath $configPath }
        else { Show-BnqqVerdicts -Profile $Profile -ConfigPath $configPath }
    }

    'apply' {
        Invoke-BnqqApply -Profile $Profile -ConfigPath $configPath -BackupDir $backupDir -WhatIf:$WhatIf -SkipRestorePoint:$SkipRestorePoint -System $system
    }

    'revert' {
        if (-not $BackupFile) {
            $latest = Get-ChildItem -LiteralPath $backupDir -Filter 'backup-*.json' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $latest) { throw 'Nenhum backup encontrado' }
            $BackupFile = $latest.FullName
        }

        Write-Bnqq ('Restaurando: {0}' -f $BackupFile) 'STEP'
        $count = Restore-BnqqBackup -File $BackupFile
        Remove-BnqqAudioTask
        Write-Bnqq ('{0} valores restaurados' -f $count) 'OK'
        Write-Bnqq 'Reinicie para concluir' 'WARN'
    }

    'status' {
        Show-BnqqStatus -System $system -Tier $tier
    }

    'watch' {
        switch ($WatcherAction) {
            'install' {
                if ($system.IsLaptop) { Install-BnqqWatcher -PinPhysical:$PinPhysical -RespectBattery }
                else { Install-BnqqWatcher -PinPhysical:$PinPhysical }
            }
            'remove'  { Uninstall-BnqqWatcher }
            'run'     { Start-BnqqWatcher -PinPhysical:$PinPhysical -RespectBattery:$system.IsLaptop }
            default   { Show-BnqqWatcherStatus }
        }
    }

    'menu' {
        Invoke-BnqqTui
    }

    'focus' { Start-BnqqFocus }
    'unfocus' { Stop-BnqqFocus }
    'trim' { Invoke-BnqqTrim | Out-Null }
    'rebalance' { Invoke-BnqqRebalance -Seconds 60 }
    'stress' { Invoke-BnqqStress -Seconds 15 }

    'stability' {
        Test-BnqqStability -Minutes $StabilityMinutes -Seconds $StabilitySeconds -Threads $StabilityThreads -ReportDir $reportDir
    }

    'timer' { Show-BnqqTimerStatus }

    'qos' { Show-BnqqQosStatus }

    'audio' {
        switch ($AudioAction) {
            'install' {
                Set-BnqqAudioIsolation -Core $AudioCore
                $saved = Save-BnqqBackup -Directory $backupDir
                if ($saved) { Write-Bnqq ('Backup: {0}' -f $saved) 'OK' }
            }
            'remove' { Remove-BnqqAudioTask }
            default { Show-BnqqAudioStatus }
        }
    }

    'guide' { Show-BnqqGuide }
    'debloat' { Show-BnqqDebloat }
    'cache' { Clear-BnqqShaderCaches }
    'bench' { Invoke-BnqqBench }
    'bcd' { Show-BnqqBcd }

    'help' {
        Write-Host ''
        Write-Host '  BNQQ TOOLKIT' -ForegroundColor Cyan
        Write-Host '  Otimizacao real e reversivel para Windows 10/11' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  INTERATIVO' -ForegroundColor White
        Write-Host '    .\bnqq.ps1                    TUI: deep scan, apply, revert, watcher' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 menu               Mesmo que sem parametros' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 watch              Status do watcher de jogos' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 watch -WatcherAction install [-PinPhysical]' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 watch -WatcherAction remove' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 watch -WatcherAction run    Primeiro plano' -ForegroundColor Gray
        Write-Host ''
        Write-Host '  DIAGNOSTICO' -ForegroundColor White
        Write-Host '    .\bnqq.ps1 scan                 Hardware, BIOS, OS e achados' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 report               Score por area com prioridades' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 verdict              O que funciona e o que e placebo' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 stress               Boost sustentado e throttling' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 stability            5 min de carga + WHEA 18/19 (Curve Optimizer)' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 stability -StabilityMinutes 3' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 timer                Timer resolution atual (0.5 ms com watcher)' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 qos                  Politicas DSCP 46 e QoS Packet Scheduler' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 audio                Isolamento do audiodg e Audio Enhancements' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 audio -AudioAction install -AudioCore 5' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 audio -AudioAction remove' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 bench                CPU, fila e disco em 10s' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 bcd                  Estado do boot (BCD)' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 status               Resumo do que esta ativo' -ForegroundColor Gray
        Write-Host ''
        Write-Host '  OTIMIZACAO' -ForegroundColor White
        Write-Host '    .\bnqq.ps1 apply                Aplica perfil automatico' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 apply -Profile lowend    PC fraco / 8 GB' -ForegroundColor DarkGray
        Write-Host '    .\bnqq.ps1 apply -Profile laptop    notebook, respeita bateria' -ForegroundColor DarkGray
        Write-Host '    .\bnqq.ps1 apply -Profile desktop   equilibrado' -ForegroundColor DarkGray
        Write-Host '    .\bnqq.ps1 apply -Profile gaming    agressivo' -ForegroundColor DarkGray
        Write-Host '    .\bnqq.ps1 apply -Profile fresh     pos-formatacao, tudo' -ForegroundColor DarkGray
        Write-Host '    .\bnqq.ps1 apply -Profile extreme   fresh + mitigacoes off (risco alto)' -ForegroundColor DarkGray
        Write-Host '    .\bnqq.ps1 apply -WhatIf        Mostra sem aplicar' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 revert               Desfaz o ultimo apply' -ForegroundColor Gray
        Write-Host '                                    (nao reinstala apps removidos nem recursos)' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  DURANTE O JOGO' -ForegroundColor White
        Write-Host '    .\bnqq.ps1 focus                Suspende background e prioriza o jogo' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 unfocus              Restaura tudo apos a partida' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 rebalance            ProBalance por 60s' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 trim                 Libera working set de apps ociosos' -ForegroundColor Gray
        Write-Host ''
        Write-Host '  EXTRAS' -ForegroundColor White
        Write-Host '    .\bnqq.ps1 guide                Ajustes in-game que dao FPS de verdade' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 debloat              Lista apps/tarefas removiveis' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 cache                Limpa caches de shader' -ForegroundColor Gray
        Write-Host ''
    }
}
