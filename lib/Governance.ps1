function Get-BnqqWheaEvents {
    param([datetime]$Since=(Get-Date).AddHours(-72))
    try {
        $events=@(Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WHEA-Logger';StartTime=$Since} -ErrorAction Stop)
        return [pscustomobject]@{Events=@($events | Where-Object {$_.Id -in @(1,17,18,19,20,46)});Error=$null}
    } catch {
        if($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*'){return [pscustomobject]@{Events=@();Error=$null}}
        return [pscustomobject]@{Events=@();Error=$_.Exception.Message}
    }
}
function Assert-BnqqWheaBaseline {
    $probe=Get-BnqqWheaEvents
    if($probe.Error){throw ('Historico WHEA indeterminado: '+$probe.Error)}
    if(@($probe.Events).Count){throw 'WHEA recente (72h): ajuste bloqueado. Investigue estabilidade; nao limpe o log para contornar a verificacao.'}
}
function Get-BnqqConfigurationFingerprint {
    # Do not trust board names or HWIDs. Any missing required input invalidates the attestation.
    $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cpu=Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    $gpu=@(Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object Name,DriverVersion)
    $mem=@(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop | Select-Object Capacity,ConfiguredClockSpeed)
    if(-not $cpu -or -not $gpu.Count -or -not $mem.Count){throw 'Fingerprint incompleto'}
    $source=@(Get-ChildItem (Join-Path $script:BnqqRoot 'lib') -File | Sort-Object Name | ForEach-Object {(Get-FileHash $_.FullName -Algorithm SHA256 -ErrorAction Stop).Hash})
    $registry=@(Get-BnqqRegistryTargets | ForEach-Object {Get-RegSnapshot $_.Path $_.Name})
    $state=[ordered]@{Boot=$os.LastBootUpTime.ToUniversalTime().ToString('o');Build=$os.BuildNumber;CPU=$cpu.Name;Threads=$cpu.NumberOfLogicalProcessors;GPU=$gpu;Memory=$mem;Power=(Get-BnqqPowerSnapshot);Registry=$registry;Sources=$source}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($state|ConvertTo-Json -Depth 8 -Compress))))).Replace('-','')}
    finally{$sha.Dispose()}
}
function Get-BnqqLatestHeavyQa {
    param([int]$MaxAgeHours=24)
    $file=Join-Path (Get-BnqqDataRoot) 'heavyqa.json'
    if(-not (Test-Path $file)){return $null}
    try {
        $d=Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json
        $age=([datetime]::UtcNow-[datetime]::Parse($d.Generated).ToUniversalTime()).TotalHours
        $passed=$d.Schema -eq 2 -and $d.Verdict -eq 'PASS' -and $d.CpuVerified -and $d.IoVerified -and $d.Completed -and $d.Seconds -ge 600 -and $d.IdleTailSeconds -ge 30 -and $d.WheaCount -eq 0 -and $age -ge 0 -and $age -le $MaxAgeHours -and $d.Owner -eq (Get-BnqqOwner) -and $d.Fingerprint -ceq (Get-BnqqConfigurationFingerprint)
        return [pscustomobject]@{Passed=$passed;File=$file;AgeHours=$age;Data=$d}
    }catch{return $null}
}
function Assert-BnqqHeavyQa {
    Assert-BnqqWheaBaseline
    $cert=Get-BnqqLatestHeavyQa
    if(-not $cert -or -not $cert.Passed){throw 'HeavyQA de 10+ minutos, completo e recente, exigido neste boot/configuracao. Execute heavyqa apos validar o codigo.'}
}
