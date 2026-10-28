[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('scan', 'apply', 'revert', 'help')]
    [string]$Command = 'scan',

    [string]$Profile = 'auto',
    [string]$BackupFile,
    [switch]$WhatIf,
    [switch]$NoRestorePoint,
    [switch]$NoElevate
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\Detect.ps1')
. (Join-Path $root 'lib\Tweaks.ps1')

$configPath = Join-Path $root 'config\profiles.json'
$reportDir = Join-Path $root 'reports'
$backupDir = Join-Path $root 'backups'

if ($Command -in @('apply', 'revert') -and -not (Test-Admin) -and -not $NoElevate) {
    $forward = @($Command)
    if ($Command -eq 'apply') { $forward += @('-Profile', $Profile) }
    if ($Command -eq 'revert' -and $BackupFile) { $forward += @('-BackupFile', $BackupFile) }
    if ($WhatIf) { $forward += '-WhatIf' }
    if ($NoRestorePoint) { $forward += '-NoRestorePoint' }
    Invoke-Elevation -Script $MyInvocation.MyCommand.Path -ScriptArgs $forward
}

Start-Log -Dir $reportDir | Out-Null

$system = Get-SystemInfo

if ($Profile -eq 'auto') {
    $Profile = if ($system.IsLaptop) { 'laptop' } else { 'gaming' }
}

switch ($Command) {
    'scan' {
        $findings = Get-Findings -System $system
        Show-Scan -System $system -Findings $findings

        $suggested = if ($system.IsLaptop) { 'laptop' } else { 'gaming' }
        Write-Host ('  Perfil sugerido: {0}' -f $suggested) -ForegroundColor Cyan
        Write-Host ('  Aplicar:         .\bnqq.ps1 apply -Profile {0}' -f $suggested) -ForegroundColor DarkGray
        Write-Host ''
    }

    'apply' {
        Invoke-Optimize -Profile $Profile -ConfigPath $configPath -BackupDir $backupDir -WhatIf:$WhatIf -NoRestorePoint:$NoRestorePoint -System $system
    }

    'revert' {
        if (-not $BackupFile) {
            $latest = Get-ChildItem -LiteralPath $backupDir -Filter 'backup-*.json' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $latest) { throw 'Nenhum backup encontrado' }
            $BackupFile = $latest.FullName
        }

        Write-Step ('Restaurando: {0}' -f $BackupFile)
        $count = Restore-Backup -File $BackupFile
        Write-Log ('{0} valores restaurados' -f $count) 'OK'
        Write-Log 'Reinicie para concluir' 'WARN'
    }

    'help' {
        Write-Host ''
        Write-Host '  BNQQ TOOLKIT' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '    .\bnqq.ps1 scan                 Analisa o PC e sugere perfil' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 apply                Aplica perfil automatico' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 apply -Profile laptop' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 apply -Profile desktop' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 apply -Profile gaming' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 apply -WhatIf        Mostra sem aplicar' -ForegroundColor Gray
        Write-Host '    .\bnqq.ps1 revert               Desfaz o ultimo apply' -ForegroundColor Gray
        Write-Host ''
        Write-Host '  Perfis:' -ForegroundColor White
        Write-Host '    laptop    conservador, respeita bateria e DC' -ForegroundColor DarkGray
        Write-Host '    desktop   equilibrado, sem desligar HVCI' -ForegroundColor DarkGray
        Write-Host '    gaming    agressivo, HVCI off, core parking off' -ForegroundColor DarkGray
        Write-Host ''
    }
}
