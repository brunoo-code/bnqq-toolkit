#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Apply,[string]$AdapterName)
$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($n in @('Core','Governance','CpuSession','StorageMemory','NicPolicy')){. (Join-Path $script:BnqqRoot ('lib\'+$n+'.ps1'))}
$r=[pscustomobject]@{Schema='BNQQ.Phase3.1';Started=[datetime]::UtcNow.ToString('o');Memory=$null;Vectors=@();Health=$null;PerformanceMeasured=$false}
try{$r.Memory=Get-BnqqMemoryReport}catch{Write-BnqqNightLog 'PHASE3-MEMORY-UNKNOWN' $_.Exception.Message}
foreach($vector in @('NVMe','NIC')){
    $e=[pscustomobject]@{Vector=$vector;Status='Preview';Result=$null;Journal=$null;Error=$null;Rollback=$null}
    try {
        if($vector -eq 'NVMe'){$action=if($Apply){'apply'}else{'plan'};$e.Result=Invoke-BnqqNvmePolicy -Action $action}
        else{$action=if($Apply){'stage'}else{'plan'};$e.Result=Invoke-BnqqNicPolicy -Action $action -Name $AdapterName}
        $e.Status=$e.Result.Status;$e.Journal=$e.Result.Journal
    }catch{$e.Status='BlockedOrFailed';$e.Error=$_.Exception.Message;$e.Journal=$_.Exception.Data['BnqqJournal'];Write-BnqqNightLog ('PHASE3-'+$vector+'-FAILED') $e.Error}
    $r.Vectors+=@($e)
}
$r.Health=Get-BnqqPhaseHealth -Since (Get-Date).AddHours(-72)
if(-not $r.Health.Healthy){
    foreach($e in $r.Vectors){
        if($e.Journal){
            try{& (Join-Path $PSScriptRoot 'Incident-Rollback.ps1') -BackupFile $e.Journal|Out-Null;$e.Rollback='Verified';$e.Status='RestoredForHealth'}
            catch{$e.Rollback='NeedsRecovery';Write-BnqqNightLog 'PHASE3-RECOVERY-FAILED' $_.Exception.Message}
        }else{$e.Rollback='NoCurrentMutation'}
    }
    Write-BnqqNightLog 'PHASE3-HEALTH' ($r.Health|ConvertTo-Json -Compress)
}
$file=Join-Path (Get-BnqqDataRoot) ('phases\phase3-'+[guid]::NewGuid().ToString('N')+'.json')
Write-BnqqAtomicJson $r $file;Write-Host ('Fase 3: '+$file)
$r|ConvertTo-Json -Depth 15
