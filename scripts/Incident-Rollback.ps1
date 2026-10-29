#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$taskName = 'BNQQ Game Watcher'
$processor = '54533251-82be-4824-96c1-47b60b740d00'
$idleDisable = '5d76a2ca-e8c0-402f-a133-2158492d58ad'
$idleDemote = '4b92d758-5a24-4851-a470-815d78aee119'
$idlePromote = '7b224883-b3cc-4d79-819f-8374152cbe7c'

$scheme = (powercfg /getactivescheme) -join ' '
$guid = [regex]::Match($scheme, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
if (-not $guid) { throw 'Plano de energia ativo nao identificado' }

Write-Host 'Incident rollback: desativando idle/C-states e watcher...' -ForegroundColor Yellow

foreach ($value in @(
    @($idleDisable, 0),
    @($idleDemote, 40),
    @($idlePromote, 60)
)) {
    & powercfg /setacvalueindex $guid $processor $value[0] $value[1] 2>$null | Out-Null
    & powercfg /setdcvalueindex $guid $processor $value[0] $value[1] 2>$null | Out-Null
}
& powercfg /setactive $guid 2>$null | Out-Null

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
}

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*bnqq-watch.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$idle = powercfg /query SCHEME_CURRENT $processor $idleDisable 2>$null | Select-String '0x' | Select-Object -Last 2
Write-Host ''
Write-Host '  ROLLBACK APLICADO' -ForegroundColor Cyan
Write-Host ('    Processor Idle Disable: {0}' -f (($idle -join ' ') -replace '\s+', ' ')) -ForegroundColor Gray
Write-Host '    Watcher: parado e desabilitado no logon' -ForegroundColor Gray
Write-Host '    Process Lasso: encerrado junto com o watcher' -ForegroundColor Gray
Write-Host ''
Write-Host 'BIOS: coloque PBO em Auto/Disabled e Curve Optimizer em 0.' -ForegroundColor Yellow
Write-Host 'Depois de estabilizar, reative o watcher com:' -ForegroundColor Yellow
Write-Host '  Enable-ScheduledTask -TaskName "BNQQ Game Watcher"; Start-ScheduledTask -TaskName "BNQQ Game Watcher"' -ForegroundColor Gray
