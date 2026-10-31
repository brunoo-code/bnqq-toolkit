# One foreground-aware resource controller; no game configuration or clock changes.
function Get-BnqqCompetitionHardware {
    $errors=@();$gpus=@();$cpus=@()
    try{
        $observed=@(Get-CimInstance Win32_VideoController -OperationTimeoutSec 5 -ErrorAction Stop)
        if($observed.Count -gt 16){throw 'Inventario GPU ambiguo/grande demais'}
        $gpus=@(foreach($g in $observed){
            $id=[string]$g.PNPDeviceID;$vendor='Unknown'
            if($id -match '^PCI\\VEN_(10DE|1002|8086)(?:&|$)'){$vendor=@{'10DE'='NVIDIA';'1002'='AMD';'8086'='Intel'}[$Matches[1].ToUpperInvariant()]}
            [pscustomobject]@{Name=$g.Name;DriverVersion=$g.DriverVersion;ObservedPciVendor=$vendor;GpuWritesInThisSession=$false;BackendPolicy=$(if($vendor -eq 'NVIDIA'){'NVAPI separate opt-in command with signature/profile checks'}else{'Inventory only; no NVIDIA settings reused'})}
        })
    }catch{$errors+=('GPU: '+$_.Exception.Message)}
    try{$cpus=@(Get-CimInstance Win32_Processor -OperationTimeoutSec 5 -ErrorAction Stop|Select-Object Name,NumberOfCores,NumberOfLogicalProcessors)}catch{$errors+=('CPU: '+$_.Exception.Message)}
    [pscustomobject]@{Status=$(if($errors.Count){'Partial'}else{'Observed'});Cpu=$cpus;Gpu=$gpus;Errors=$errors;BoardFirmwareTrusted=$false;PboCurveOptimizer='NotMeasured';Policy='Priority resource policy does not depend on GPU vendor or assumed SMBIOS board'}
}
function Get-BnqqCompetitionPlan {
    param([string[]]$Apps,[string[]]$UploadApps,[int]$UploadKbps=512,[switch]$PauseSearch,[switch]$DeferMaintenance,[ValidateSet('cs2.exe','VALORANT-Win64-Shipping.exe')][string]$Game='cs2.exe')
    if(-not @($Apps).Count){$Apps=Get-BnqqBudgetAllowedApps}
    $focus=Get-BnqqFocusPlan -Apps $Apps -Policy Priority -PauseSearch:$PauseSearch -DeferMaintenance:$DeferMaintenance
    $network=Get-BnqqNetworkSessionPlan -Apps $UploadApps -UploadKbps $UploadKbps
    [pscustomobject]@{Schema='BNQQ.CompetitionPlan.1';Game=$Game;Hardware=(Get-BnqqCompetitionHardware);Readiness=(Get-BnqqReadiness);Focus=$focus;Upload=$network;ChangesGameConfig=$false;ChangesPowerClock=$false;ChangesGpuDriver=$false;RequiresAdmin=($focus.Maintenance.RequiresAdmin -or @($UploadApps).Count -gt 0);MeasuredPerformanceGain=$null;Note='One controller for dynamic CPU priority plus explicitly selected maintenance/upload leases. No automatic NIC, timer, shader-cache or security changes.'}
}
function Invoke-BnqqCompetitionSession {
    param([ValidateSet('plan','run','stop','status')][string]$Action='plan',[string[]]$Apps,[string[]]$UploadApps,[ValidateRange(64,1000000)][int]$UploadKbps=512,
        [switch]$PauseSearch,[switch]$DeferMaintenance,[ValidateSet('cs2.exe','VALORANT-Win64-Shipping.exe')][string]$Game='cs2.exe',[ValidateRange(1,240)][int]$MaxMinutes=120)
    if($Action -eq 'stop'){return (Stop-BnqqFocusSession)}
    if($Action -eq 'status'){return (Get-BnqqFocusStatus)}
    $plan=Get-BnqqCompetitionPlan -Apps $Apps -UploadApps $UploadApps -UploadKbps $UploadKbps -PauseSearch:$PauseSearch -DeferMaintenance:$DeferMaintenance -Game $Game
    if($Action -eq 'plan'){return $plan}
    # The real gate is rechecked inside focus, never trust a preview's Ready flag.
    Invoke-BnqqFocusSession -Action run -Apps $plan.Focus.Apps -Policy Priority -UploadApps $UploadApps -UploadKbps $UploadKbps -PauseSearch:$PauseSearch -DeferMaintenance:$DeferMaintenance -Game $Game -MaxMinutes $MaxMinutes
}
