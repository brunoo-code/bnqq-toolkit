# Read-only inventory. WMI observations are neither a benchmark nor attestation.
function Get-BnqqDriverSource {
    param([ValidateSet('Win32_PnPEntity','Win32_PnPSignedDriver','Win32_SystemDriver')][string]$Class)
    $rows=@(Get-CimInstance -ClassName $Class -OperationTimeoutSec 5 -ErrorAction Stop)
    if($rows.Count -gt 4096){throw 'Inventario excedeu 4096 registros por fonte'}
    return $rows
}
function Get-BnqqDriverModuleName {
    param([string]$Path)
    $text=$Path.Trim()
    if($text.StartsWith('"')){$m=[regex]::Match($text,'(?i)^"([^"\r\n]+\.sys)"(?:\s.*)?$')}
    else{
        if([regex]::Matches($text,'(?i)\.sys\b').Count -ne 1){return $null}
        $m=[regex]::Match($text,'(?i)^([^"\r\n]+?\.sys)(?:\s.*)?$')
    }
    if($m.Success){return [IO.Path]::GetFileName($m.Groups[1].Value).ToLowerInvariant()}
    return $null
}
function Get-BnqqDriverAudit {
    $data=@{};$sources=@();$errors=@()
    foreach($class in @('Win32_PnPEntity','Win32_PnPSignedDriver','Win32_SystemDriver')){
        try{
            $data[$class]=@(Get-BnqqDriverSource $class)
            $sources+=@([pscustomobject]@{Class=$class;Status='Read';Rows=$data[$class].Count})
        }catch{
            $data[$class]=@();$errors+=($class+': '+$_.Exception.Message)
            $sources+=@([pscustomobject]@{Class=$class;Status='Unavailable';Rows=$null})
        }
    }
    $byDevice=@{};$byService=@{}
    foreach($d in $data.Win32_PnPSignedDriver){
        if(-not $d.DeviceID){continue};$key=[string]$d.DeviceID
        if(-not $byDevice.ContainsKey($key)){$byDevice[$key]=@()};$byDevice[$key]+= @($d)
    }
    foreach($d in $data.Win32_SystemDriver){
        if(-not $d.Name){continue};$key=[string]$d.Name
        if(-not $byService.ContainsKey($key)){$byService[$key]=@()};$byService[$key]+= @($d)
    }
    $devices=@(foreach($d in $data.Win32_PnPEntity){
        if($d.PNPClass -notin @('Display','Net','Media','USB','HIDClass','SCSIAdapter','HDC','System')){continue}
        $packages=@(if($d.DeviceID -and $byDevice.ContainsKey([string]$d.DeviceID)){$byDevice[[string]$d.DeviceID]})
        $services=@(if($d.Service -and $byService.ContainsKey([string]$d.Service)){$byService[[string]$d.Service]})
        [pscustomobject]@{
            DeviceId=$d.DeviceID;Name=$d.Name;Class=$d.PNPClass;Present=$d.Present;Status=$d.Status;ProblemCode=$d.ConfigManagerErrorCode;Service=$d.Service
            PackageMatch=$(if($packages.Count -eq 1){'Single'}elseif($packages.Count -gt 1){'Multiple'}else{'Missing'})
            Packages=@($packages|ForEach-Object {[pscustomobject]@{Provider=$_.DriverProviderName;Version=$_.DriverVersion;Inf=$_.InfName;SignedReported=$(if($_.IsSigned -is [bool]){$_.IsSigned}else{$null});Signer=$_.Signer}})
            ServiceMatch=$(if($services.Count -eq 1){'Single'}elseif($services.Count -gt 1){'Multiple'}else{'Missing'})
            ServiceModules=@($services|ForEach-Object {[pscustomobject]@{Name=$_.Name;State=$_.State;Module=(Get-BnqqDriverModuleName $_.PathName)}})
        }
    })
    $modules=@(foreach($d in $data.Win32_SystemDriver){
        $module=Get-BnqqDriverModuleName $d.PathName
        if($d.State -eq 'Running' -and $module){[pscustomobject]@{Module=$module;Service=$d.Name;DisplayName=$d.DisplayName;StartMode=$d.StartMode}}
    })
    [pscustomobject]@{
        Schema='BNQQ.DriverAudit.1';Generated=[datetime]::UtcNow.ToString('o')
        Status=$(if($errors.Count -eq 3){'Unavailable'}elseif($errors.Count){'Partial'}else{'Complete'})
        Sources=$sources;Devices=$devices;RunningModules=$modules;Errors=$errors
        ReportedDeviceProblems=@($devices|Where-Object {$null -ne $_.ProblemCode -and $_.ProblemCode -ne 0}).Count
        DpcAttribution='NotMeasured';RecommendedDeviceChanges=@()
        Claim='Observed inventory only. No driver blamed by age, vendor, signature flag or presence. SMBIOS is not used.'
    }
}
