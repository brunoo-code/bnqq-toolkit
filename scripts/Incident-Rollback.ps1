#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BackupFile)
$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($name in @('Core','Apps','Governance','GameProfile','FramePacing','GameSession','CpuSession','ProcessSampling','BackgroundBudget','StorageMemory','Maintenance','NicPolicy','GpuDriver','NetworkSession','LegacyMigration','RecoveryHub')){
    . (Join-Path $script:BnqqRoot ('lib\'+$name+'.ps1'))
}
try{Invoke-BnqqRecovery -File $BackupFile | ConvertTo-Json -Depth 10}
catch{Write-BnqqNightLog 'INCIDENT-FAILED' $_.Exception.Message;throw}
