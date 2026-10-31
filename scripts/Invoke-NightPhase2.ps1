#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Apply)
$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($name in @('Core','Governance','CpuSession','GpuDriver')){. (Join-Path $script:BnqqRoot ('lib\'+$name+'.ps1'))}
$result=[pscustomobject]@{Schema='BNQQ.Phase2.1';Started=[datetime]::UtcNow.ToString('o');Status='Preview';Support=$null;ShaderCache=$null;Games=@();Health=$null;PerformanceMeasured=$false}
try {
    $result.Support=Get-BnqqGpuSupport
    if($result.Support.Status -ne 'NvidiaAvailable'){$result.Status='UnsupportedOrUnavailable'}
    else {
        try{$result.ShaderCache=Get-BnqqShaderCacheAudit}catch{Write-BnqqNightLog 'PHASE2-CACHE-READ' $_.Exception.Message}
        foreach($game in @('cs2.exe','VALORANT-Win64-Shipping.exe')){
            $entry=[pscustomobject]@{Game=$game;Status='Preview';Result=$null;Journal=$null;Error=$null;Rollback=$null}
            try {
                $action=if($Apply){'apply'}else{'plan'}
                $entry.Result=Invoke-BnqqGpuProfile -Action $action -Game $game
                $entry.Status=$entry.Result.Status;$entry.Journal=$entry.Result.Journal
            }catch{$entry.Status='BlockedOrFailed';$entry.Error=$_.Exception.Message;$entry.Journal=$_.Exception.Data['BnqqJournal'];Write-BnqqNightLog 'PHASE2-GPU-FAILED' $entry.Error}
            $result.Games+=@($entry)
        }
        $result.Status='CompletedChecks'
    }
}catch{$result.Status='Failed';Write-BnqqNightLog 'PHASE2-FAILED' $_.Exception.Message}
finally {
    $result.Health=Get-BnqqPhaseHealth -Since (Get-Date).AddHours(-72)
    if(-not $result.Health.Healthy){
        foreach($entry in @($result.Games)){
            if($entry.Journal){
                try{& (Join-Path $PSScriptRoot 'Incident-Rollback.ps1') -BackupFile $entry.Journal|Out-Null;$entry.Rollback='Verified';$entry.Status='RestoredForHealth'}
                catch{$entry.Rollback='NeedsRecovery';Write-BnqqNightLog 'PHASE2-RECOVERY-FAILED' $_.Exception.Message}
            }else{$entry.Rollback='NoCurrentMutation'}
        }
        Write-BnqqNightLog 'PHASE2-HEALTH' ($result.Health|ConvertTo-Json -Compress)
    }
    $file=Join-Path (Get-BnqqDataRoot) ('phases\phase2-'+[guid]::NewGuid().ToString('N')+'.json')
    Write-BnqqAtomicJson $result $file
    Write-Host ('Fase 2: '+$file)
}
$result|ConvertTo-Json -Depth 15
