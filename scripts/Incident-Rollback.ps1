#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BackupFile)
$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $script:BnqqRoot 'lib\Core.ps1')
. (Join-Path $script:BnqqRoot 'lib\Apps.ps1')
if(-not (Test-BnqqAdmin)){throw 'Restauracao exige administrador'}
$lock=Enter-BnqqStateLock
try{Restore-BnqqJournal -File $BackupFile | ConvertTo-Json -Depth 8}finally{$lock.Dispose()}
