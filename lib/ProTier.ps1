$script:BnqqProNetworkPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
$script:BnqqProUsbSub = '2a737441-1930-4402-8d77-b2bebba308a3'
$script:BnqqProUsbSetting = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'

function Get-BnqqProUsbSuspend {
    $schemeOut = (powercfg /getactivescheme) -join ' '
    $scheme = [regex]::Match($schemeOut, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
    if (-not $scheme) { return [pscustomobject]@{ Ac = $null; Dc = $null; Ok = $false; Scheme = $null } }

    $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\{0}\{1}\{2}' -f $scheme, $script:BnqqProUsbSub, $script:BnqqProUsbSetting
    try {
        $props = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
        $ac = [int]$props.ACSettingIndex
        $dc = [int]$props.DCSettingIndex
        return [pscustomobject]@{ Ac = $ac; Dc = $dc; Ok = ($ac -eq 0 -and $dc -eq 0); Scheme = $scheme }
    }
    catch {
        return [pscustomobject]@{ Ac = $null; Dc = $null; Ok = $false; Scheme = $scheme }
    }
}

function Get-BnqqProDynamicTick {
    try {
        $output = @(& bcdedit /enum '{current}' 2>&1)
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ Value = 'indeterminado'; Disabled = $false; Ok = $false }
        }
        $text = $output -join "`n"
        $match = [regex]::Match($text, '(?im)^\s*disabledynamictick\s+(\S+)')
        if (-not $match.Success) {
            return [pscustomobject]@{ Value = 'nao definido'; Disabled = $false; Ok = $false }
        }
        $value = $match.Groups[1].Value
        return [pscustomobject]@{ Value = $value; Disabled = ($value -match '^(Yes|Sim)$'); Ok = ($value -match '^(Yes|Sim)$') }
    }
    catch {
        return [pscustomobject]@{ Value = 'indeterminado'; Disabled = $false; Ok = $false }
    }
}

function Get-BnqqProTierStatus {
    $network = Get-ItemProperty -LiteralPath $script:BnqqProNetworkPath -ErrorAction SilentlyContinue
    $throttle = if ($null -ne $network.NetworkThrottlingIndex) { $network.NetworkThrottlingIndex } else { $null }
    $responsiveness = if ($null -ne $network.SystemResponsiveness) { $network.SystemResponsiveness } else { $null }
    $usb = Get-BnqqProUsbSuspend
    $tick = Get-BnqqProDynamicTick

    $throttleOk = ($null -ne $throttle -and ($throttle -eq 4294967295 -or $throttle -eq -1))
    $responsivenessOk = ($responsiveness -eq 0)
    $allOk = $throttleOk -and $responsivenessOk -and $usb.Ok -and $tick.Ok

    return [pscustomobject]@{
        NetworkThrottlingIndex = $throttle
        NetworkOk              = $throttleOk
        SystemResponsiveness   = $responsiveness
        ResponsivenessOk       = $responsivenessOk
        UsbAc                  = $usb.Ac
        UsbDc                  = $usb.Dc
        UsbOk                  = $usb.Ok
        DynamicTick            = $tick.Value
        DynamicTickOk          = $tick.Ok
        AllOk                  = $allOk
    }
}

function Set-BnqqProTier {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para aplicar o Pro-Tier' }

    Set-BnqqReg $script:BnqqProNetworkPath 'NetworkThrottlingIndex' 4294967295 'DWord'
    Set-BnqqReg $script:BnqqProNetworkPath 'SystemResponsiveness' 0 'DWord'
    Set-BnqqPowerValue $script:BnqqProUsbSub $script:BnqqProUsbSetting 0
    Set-BnqqBcdDynamicTick -Disable $true
    Set-BnqqMeta 'ProTierApplied' $true

    Write-Bnqq 'Pro-Tier: network throttling off, responsiveness 0, USB suspend off, dynamic tick disabled (reboot)' 'OK'
}

function Reset-BnqqProTier {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para remover o Pro-Tier' }

    Set-BnqqReg $script:BnqqProNetworkPath 'NetworkThrottlingIndex' 10 'DWord'
    Set-BnqqReg $script:BnqqProNetworkPath 'SystemResponsiveness' 20 'DWord'
    Set-BnqqPowerValue $script:BnqqProUsbSub $script:BnqqProUsbSetting 1
    Set-BnqqBcdDynamicTick -Disable $false
    Set-BnqqMeta 'ProTierApplied' $false

    Write-Bnqq 'Pro-Tier removido: valores de rede/USB padrao e dynamic tick liberado (reboot)' 'OK'
}

function Show-BnqqProTierStatus {
    param($Status)

    if (-not $Status) { $Status = Get-BnqqProTierStatus }

    Write-Host ''
    Write-Host '  PRO-TIER / REDE E ENERGIA' -ForegroundColor Cyan
    $networkColor = if ($Status.NetworkOk) { 'Green' } else { 'Yellow' }
    $responseColor = if ($Status.ResponsivenessOk) { 'Green' } else { 'Yellow' }
    $usbColor = if ($Status.UsbOk) { 'Green' } else { 'Yellow' }
    $tickColor = if ($Status.DynamicTickOk) { 'Green' } else { 'Yellow' }

    Write-Host ('    NetworkThrottlingIndex  {0}  [{1}]' -f $Status.NetworkThrottlingIndex, $(if ($Status.NetworkOk) { 'OK' } else { 'PENDENTE' })) -ForegroundColor $networkColor
    Write-Host ('    SystemResponsiveness    {0}  [{1}]' -f $Status.SystemResponsiveness, $(if ($Status.ResponsivenessOk) { 'OK' } else { 'PENDENTE' })) -ForegroundColor $responseColor
    Write-Host ('    USB selective suspend   AC={0} DC={1}  [{2}]' -f $Status.UsbAc, $Status.UsbDc, $(if ($Status.UsbOk) { 'OK' } else { 'PENDENTE' })) -ForegroundColor $usbColor
    Write-Host ('    disabledynamictick      {0}  [{1}]' -f $Status.DynamicTick, $(if ($Status.DynamicTickOk) { 'OK' } else { 'PENDENTE' })) -ForegroundColor $tickColor
    Write-Host '    Nota                    dynamic tick off e opt-in: no Win11 pode reduzir FPS; use para teste A/B' -ForegroundColor DarkGray
    Write-Host ''
}
