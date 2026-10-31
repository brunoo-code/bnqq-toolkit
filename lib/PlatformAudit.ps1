# Read-only platform observations. No boot, security, timer or device mutation.
function Get-BnqqBootTimerSource {
    $exe=Join-Path $env:SystemRoot 'System32\bcdedit.exe'
    $lines=& $exe /enum '{current}' 2>&1
    if($LASTEXITCODE -ne 0){throw ('BCD leitura falhou: '+($lines -join ' '))}
    return @($lines|ForEach-Object {[string]$_})
}
function Get-BnqqTimerAudit {
    $keys=@('useplatformclock','useplatformtick','disabledynamictick','tscsyncpolicy');$errors=@();$rows=@();$known=$true
    try{$lines=@(Get-BnqqBootTimerSource)}catch{$lines=@();$known=$false;$errors+=$_.Exception.Message}
    foreach($key in $keys){
        $matches=@($lines|Where-Object {$_ -match ('^\s*'+$key+'\s+(.+?)\s*$')})
        $present=$null;$raw=$null
        if($known){
            if($matches.Count -gt 1){$errors+=('Entrada BCD duplicada: '+$key)}
            else{$present=($matches.Count -eq 1);if($present){$raw=[regex]::Match($matches[0],('^\s*'+$key+'\s+(.+?)\s*$')).Groups[1].Value}}
        }
        $rows+=@([pscustomobject]@{Key=$key;ExplicitOverridePresent=$present;RawValue=$raw})
    }
    $hpet=@()
    try{$hpet=@(Get-BnqqDriverSource 'Win32_PnPEntity'|Where-Object {$_.DeviceID -match '^ACPI\\PNP0103(?:\\|$)'}|Select-Object DeviceID,Name,Present,ConfigManagerErrorCode)}catch{$errors+=$_.Exception.Message}
    [pscustomobject]@{Schema='BNQQ.TimerAudit.1';Status=$(if($errors.Count){'Partial'}else{'Complete'});BootTimerOverrides=$rows;HpetDevices=$hpet;Errors=$errors;Changed=$false;Claim='Explicit boot entries and PnP state only. Missing entries do not identify the active clock. HPET disabled does not prove the cause of WHEA or frametime issues.'}
}
function Get-BnqqDeviceGuardSource {
    Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -OperationTimeoutSec 5 -ErrorAction Stop
}
function Get-BnqqSecurityAudit {
    try{
        $rows=@(Get-BnqqDeviceGuardSource)
        if($rows.Count -ne 1){throw 'Win32_DeviceGuard ambiguo/ausente'}
        $v=$rows[0].VirtualizationBasedSecurityStatus
        $state=if($null -ne $v -and [string]$v -in @('0','1','2')){@{0='NotEnabled';1='EnabledNotRunning';2='Running'}[[int]$v]}else{'Unknown'}
        [pscustomobject]@{Schema='BNQQ.SecurityAudit.1';Status='Read';VbsStatus=$state;RawVbsStatus=$v;Configured=@($rows[0].SecurityServicesConfigured);Running=@($rows[0].SecurityServicesRunning);Changed=$false;Error=$null;AntiCheatCompatibility='NotTested';Claim='Reported security state, not measured overhead. No VBS/HVCI, TPM, Secure Boot or anti-cheat bypass.'}
    }catch{[pscustomobject]@{Schema='BNQQ.SecurityAudit.1';Status='Unavailable';VbsStatus='Unknown';Configured=@();Running=@();Changed=$false;Error=$_.Exception.Message;AntiCheatCompatibility='NotTested'}}
}
function Get-BnqqUsbParent {
    param([string]$InstanceId)
    $p=@(Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop)
    if($p.Count -ne 1){throw 'Propriedade Parent ambigua/ausente'}
    if($null -eq $p[0].Data -or [string]::IsNullOrWhiteSpace([string]$p[0].Data)){return $null}
    if($p[0].Data -isnot [string] -or $p[0].Data.Length -gt 1024 -or $p[0].Data -match '[\r\n\x00]'){throw 'Identidade Parent invalida'}
    return $p[0].Data
}
function Get-BnqqUsbTopologyAudit {
    $errors=@();$nodes=@{};$parents=@{};$results=@()
    try{$devices=@(Get-BnqqDriverSource 'Win32_PnPEntity')}catch{return [pscustomobject]@{Schema='BNQQ.UsbTopology.1';Status='Unavailable';Peripherals=@();Errors=@($_.Exception.Message);PollingRateMeasured=$false;Changed=$false}}
    foreach($d in $devices){if($d.DeviceID){$nodes[[string]$d.DeviceID]=$d}}
    $endpoints=@($devices|Where-Object {$_.PNPClass -in @('Mouse','Keyboard') -and $_.Present -ne $false})
    if($endpoints.Count -gt 32){throw 'Mais de 32 interfaces Mouse/Keyboard; inventario recusado, sem truncamento silencioso'}
    foreach($device in $endpoints){
        $path=@();$seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $cursor=[string]$device.DeviceID;$controller=$null;$status='NoUsbControllerObserved'
        for($depth=0;$depth -lt 12;$depth++){
            if(-not $seen.Add($cursor)){$status='Cycle';$errors+=('Ciclo de topologia: '+$device.DeviceID);break}
            $path+=@($cursor)
            if($nodes.ContainsKey($cursor) -and $nodes[$cursor].Service -in @('USBXHCI','USBEHCI','USBUHCI','USBOHCI')){$controller=$cursor;$status='ControllerObserved';break}
            if(-not $parents.ContainsKey($cursor)){
                if($parents.Count -ge 128){$status='BoundReached';$errors+='Limite de 128 leituras Parent';break}
                try{$parents[$cursor]=[pscustomobject]@{Parent=(Get-BnqqUsbParent $cursor);Error=$null}}
                catch{$parents[$cursor]=[pscustomobject]@{Parent=$null;Error=$_.Exception.Message}}
            }
            if($parents[$cursor].Error){$status='UnknownParent';$errors+=($cursor+': '+$parents[$cursor].Error);break}
            if(-not $parents[$cursor].Parent){break}
            $cursor=$parents[$cursor].Parent
            if($depth -eq 11){$status='BoundReached';$errors+=('Limite de profundidade: '+$device.DeviceID)}
        }
        $results+=@([pscustomobject]@{InterfaceId=$device.DeviceID;Name=$device.Name;Class=$device.PNPClass;Present=$device.Present;Status=$status;ControllerId=$controller;ParentPath=$path})
    }
    $groups=@($results|Where-Object ControllerId|Group-Object ControllerId|ForEach-Object {[pscustomobject]@{ControllerId=$_.Name;LogicalInterfaces=$_.Count}})
    [pscustomobject]@{Schema='BNQQ.UsbTopology.1';Status=$(if($errors.Count){'Partial'}else{'Complete'});Peripherals=$results;Controllers=$groups;ParentQueries=$parents.Count;Errors=$errors;PollingRateMeasured=$false;Changed=$false;Claim='Logical input interfaces and observed USB ancestry, not physical peripheral count, polling rate or interrupt latency. Shared controller is not proof of interference. No IRQ/device changes.'}
}
