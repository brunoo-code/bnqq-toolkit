#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Apply,[string[]]$Apps=@('msedge','chrome','firefox','Discord','OneDrive'),
    [ValidateRange(1,16)][int]$BackgroundCores=2,[switch]$UnparkCpu,
    [ValidateSet('cs2.exe','VALORANT-Win64-Shipping.exe')][string]$Game='cs2.exe')
$ErrorActionPreference='Stop'
$phaseStarted=Get-Date
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($name in @('Core','Governance','CpuSession','GameSession')){. (Join-Path $script:BnqqRoot ('lib\'+$name+'.ps1'))}
$result=[pscustomobject]@{Schema='BNQQ.Phase1.1';Started=[datetime]::UtcNow.ToString('o');Status='Preview';Plan=$null;Result=$null;Error=$null;Health=$null;HistoricHealth72h=$null;Journal=$null;Rollback=$null;PerformanceMeasured=$false}
try {
    $result.Plan=Get-BnqqCpuSessionPlan $Apps $BackgroundCores -UnparkCpu:$UnparkCpu
    if($Apply){
        $result.Result=Invoke-BnqqCpuSession -Action run -Apps $Apps -BackgroundCores $BackgroundCores -UnparkCpu:$UnparkCpu -Game $Game
        $result.Status=$result.Result.Status;$result.Journal=$result.Result.Journal
    }
}catch{
    $result.Status='BlockedOrFailed';$result.Error=$_.Exception.Message
    $result.Journal=$_.Exception.Data['BnqqJournal']
    Write-BnqqNightLog 'PHASE1-FAILED' $result.Error
}finally{
    # This check does not clear logs or claim recovery from a BSOD. Only the
    # current vector's durable journal may be restored, never an unrelated backup.
    $result.Health=Get-BnqqPhaseHealth -Since $phaseStarted
$result.HistoricHealth72h=Get-BnqqPhaseHealth -Since (Get-Date).AddHours(-72)
    if(-not $result.Health.Healthy){
        if($result.Journal){
            try {
                & (Join-Path $PSScriptRoot 'Incident-Rollback.ps1') -BackupFile $result.Journal|Out-Null
                $result.Rollback='Verified'
            }catch{$result.Rollback='NeedsRecovery';Write-BnqqNightLog 'PHASE1-RECOVERY-FAILED' $_.Exception.Message}
        }else{$result.Rollback='NoCurrentMutation'}
        Write-BnqqNightLog 'PHASE1-HEALTH' ($result.Health|ConvertTo-Json -Compress)
    }
    $file=Join-Path (Get-BnqqDataRoot) ('phases\phase1-'+[guid]::NewGuid().ToString('N')+'.json')
    Write-BnqqAtomicJson $result $file
    Write-Host ('Fase 1: '+$file)
}
$result|ConvertTo-Json -Depth 15
