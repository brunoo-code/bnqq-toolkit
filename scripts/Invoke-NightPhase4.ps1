#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Apply)
$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($n in @('Core','Governance','RuntimeLatency','CpuSession','Maintenance','FocusSession')){. (Join-Path $script:BnqqRoot ('lib\'+$n+'.ps1'))}
$existing=@(Get-ChildItem -LiteralPath (Join-Path (Get-BnqqDataRoot) 'journals') -Filter '*.json' -File -ErrorAction SilentlyContinue|Select-Object -ExpandProperty FullName)
$r=[pscustomobject]@{Schema='BNQQ.Phase4.1';Started=[datetime]::UtcNow.ToString('o');Plan=$null;Status='Preview';Result=$null;Error=$null;Health=$null;Rollback='NoCurrentMutation';PerformanceMeasured=$false;RebootRequired=$false}
try{
    $r.Plan=Get-BnqqFocusPlan @('msedge','chrome','firefox','OneDrive') 2 -PauseSearch -DeferMaintenance
    if($Apply){$r.Result=Invoke-BnqqFocusSession -Action run -Apps @('msedge','chrome','firefox','OneDrive') -PauseSearch -DeferMaintenance;$r.Status=$r.Result.Status}
}catch{$r.Status='BlockedOrFailed';$r.Error=$_.Exception.Message;Write-BnqqNightLog 'PHASE4-FAILED' $r.Error}
# The session itself journals and restores both scopes in nested finally blocks.
# Historical health events do not authorize touching unrelated/previous journals.
$r.Health=Get-BnqqPhaseHealth -Since (Get-Date).AddHours(-72)
if(-not $r.Health.Healthy){
    foreach($f in @(Get-ChildItem -LiteralPath (Join-Path (Get-BnqqDataRoot) 'journals') -Filter '*.json' -File -ErrorAction SilentlyContinue)){
        if($f.FullName -in $existing){continue}
        $j=Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop|ConvertFrom-Json
        if($j.Owner -cne (Get-BnqqOwner) -or $j.Purpose -notin @('focus-cpu-epoch-v2-phase4','focus-maintenance-v2-phase4')){continue}
        if($j.Status -eq 'Restored'){$r.Rollback='AlreadyRestored';continue}
        try{& (Join-Path $PSScriptRoot 'Incident-Rollback.ps1') -BackupFile $f.FullName|Out-Null;$r.Rollback='Verified'}
        catch{$r.Rollback='NeedsRecovery';Write-BnqqNightLog 'PHASE4-RECOVERY-FAILED' $_.Exception.Message}
    }
}
$file=Join-Path (Get-BnqqDataRoot) ('phases\phase4-'+[guid]::NewGuid().ToString('N')+'.json')
Write-BnqqAtomicJson $r $file;Write-Host ('Fase 4: '+$file)
$r|ConvertTo-Json -Depth 15
