function Get-BnqqInputDevices {
    $rows = New-Object System.Collections.Generic.List[object]

    $mice = @(Get-CimInstance Win32_PointingDevice -ErrorAction SilentlyContinue)
    foreach ($m in $mice) {
        $rows.Add([pscustomobject]@{
            Kind    = 'Mouse'
            Name    = $m.Name
            Status  = $m.Status
            Buttons = $m.NumberOfButtons
            PnpId   = $m.PNPDeviceID
        })
    }

    $kbds = @(Get-CimInstance Win32_Keyboard -ErrorAction SilentlyContinue)
    foreach ($k in $kbds) {
        $rows.Add([pscustomobject]@{
            Kind    = 'Keyboard'
            Name    = $k.Description
            Status  = $k.Status
            Buttons = $null
            PnpId   = $k.PNPDeviceID
        })
    }

    return $rows
}

function Get-BnqqUsbAudit {
    $hubs = @(Get-PnpDevice -Class USB -Status OK -ErrorAction SilentlyContinue)
    $hid = @(Get-PnpDevice -Class HIDClass -Status OK -ErrorAction SilentlyContinue)

    $powerManaged = New-Object System.Collections.Generic.List[object]

    foreach ($dev in ($hubs + $hid)) {
        if (-not $dev.InstanceId) { continue }
        $paramPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\{0}\Device Parameters' -f $dev.InstanceId

        $enhanced = (Get-ItemProperty -LiteralPath $paramPath -Name EnhancedPowerManagementEnabled -ErrorAction SilentlyContinue).EnhancedPowerManagementEnabled
        $idle = (Get-ItemProperty -LiteralPath $paramPath -Name AllowIdleIrpInD3 -ErrorAction SilentlyContinue).AllowIdleIrpInD3
        $suspend = (Get-ItemProperty -LiteralPath $paramPath -Name SelectiveSuspendEnabled -ErrorAction SilentlyContinue).SelectiveSuspendEnabled

        if ($enhanced -ne 0 -or $idle -ne 0 -or $suspend -ne 0) {
            $powerManaged.Add([pscustomobject]@{
                Device   = $dev.FriendlyName
                Class    = $dev.Class
                Enhanced = $enhanced
                IdleIrp  = $idle
                Suspend  = $suspend
            })
        }
    }

    return [pscustomobject]@{
        Controllers   = @($hubs | Where-Object { $_.FriendlyName -match 'Host Controller|Root Hub' } | ForEach-Object { $_.FriendlyName })
        HidDevices    = @($hid | ForEach-Object { $_.FriendlyName })
        PowerManaged  = $powerManaged
    }
}

function Show-BnqqDevices {
    $inputs = Get-BnqqInputDevices
    $usb = Get-BnqqUsbAudit

    Write-Host ''
    Write-Host '  PERIFERICOS' -ForegroundColor Cyan
    Write-Host ''

    Write-Host '  DISPOSITIVOS DE ENTRADA' -ForegroundColor White
    foreach ($d in $inputs) {
        Write-Host ('    {0,-9} {1}' -f $d.Kind, $d.Name) -ForegroundColor Gray
    }
    Write-Host ''

    Write-Host '  CONTROLADORAS USB' -ForegroundColor White
    foreach ($c in $usb.Controllers) {
        Write-Host ('    {0}' -f $c) -ForegroundColor Gray
    }
    Write-Host ''

    Write-Host '  ECONOMIA DE ENERGIA USB' -ForegroundColor White
    if ($usb.PowerManaged.Count -eq 0) {
        Write-Host '    Nenhum dispositivo com suspensao ativa' -ForegroundColor Green
    }
    else {
        foreach ($p in $usb.PowerManaged) {
            Write-Host ('    [SUSPENSAO] {0}' -f $p.Device) -ForegroundColor Yellow
        }
        Write-Host ''
        Write-Host ('    {0} dispositivo(s) podem entrar em D3 e atrasar reconexao' -f $usb.PowerManaged.Count) -ForegroundColor Yellow
    }
    Write-Host ''
}

function Set-BnqqUsbPowerSaving {
    $devices = @(Get-PnpDevice -Class USB, HIDClass -Status OK -ErrorAction SilentlyContinue)
    $changed = 0

    foreach ($dev in $devices) {
        if (-not $dev.InstanceId) { continue }
        $paramPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\{0}\Device Parameters' -f $dev.InstanceId

        if (-not (Test-Path -LiteralPath $paramPath)) { continue }

        $props = Get-ItemProperty -LiteralPath $paramPath -ErrorAction SilentlyContinue

        if ($null -ne $props.EnhancedPowerManagementEnabled -and $props.EnhancedPowerManagementEnabled -ne 0) {
            Set-BnqqReg $paramPath 'EnhancedPowerManagementEnabled' 0
            $changed++
        }
        if ($null -ne $props.AllowIdleIrpInD3 -and $props.AllowIdleIrpInD3 -ne 0) {
            Set-BnqqReg $paramPath 'AllowIdleIrpInD3' 0
            $changed++
        }
        if ($null -ne $props.SelectiveSuspendEnabled -and $props.SelectiveSuspendEnabled -ne 0) {
            Set-BnqqReg $paramPath 'SelectiveSuspendEnabled' 0
            $changed++
        }
    }

    Write-Bnqq ('Suspensao USB desativada em {0} propriedade(s)' -f $changed) 'OK'
}

function Set-BnqqUsb3LinkPowerManagement {
    param([int]$Value = 0)

    powercfg -attributes 2a737441-1930-4402-8d77-b2bebba308a3 d4e98f31-5ffe-4ce1-be31-1b38b384c009 -ATTRIB_HIDE 2>$null | Out-Null
    Set-BnqqPowerValue '2a737441-1930-4402-8d77-b2bebba308a3' 'd4e98f31-5ffe-4ce1-be31-1b38b384c009' $Value
    Write-Bnqq ('USB 3 Link Power Management: {0}' -f $(if ($Value -eq 0) { 'desativado' } else { 'valor ' + $Value })) 'OK'
}

function Get-BnqqDisplayDeep {
    $monitors = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($m in $monitors) {
        $name = -join [char[]]($m.UserFriendlyName | Where-Object { $_ -ne 0 })
        $mfr = -join [char[]]($m.ManufacturerName | Where-Object { $_ -ne 0 })
        $rows.Add([pscustomobject]@{
            Manufacturer = $mfr
            Model        = $name
            Year         = $m.YearOfManufacture
        })
    }

    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual' } | Select-Object -First 1

    return [pscustomobject]@{
        Monitors     = $rows
        RefreshRate  = $gpu.CurrentRefreshRate
        MaxRefresh   = $gpu.MaxRefreshRate
        Width        = $gpu.CurrentHorizontalResolution
        Height       = $gpu.CurrentVerticalResolution
    }
}

function Show-BnqqDisplay {
    $d = Get-BnqqDisplayDeep

    Write-Host ''
    Write-Host '  DISPLAY' -ForegroundColor Cyan
    foreach ($m in $d.Monitors) {
        Write-Host ('    {0} {1}  ({2})' -f $m.Manufacturer, $m.Model, $m.Year) -ForegroundColor Gray
    }
    $color = if ($d.RefreshRate -ge 144) { 'Green' } else { 'Yellow' }
    Write-Host ('    {0} x {1} @ {2} Hz  (max {3} Hz)' -f $d.Width, $d.Height, $d.RefreshRate, $d.MaxRefresh) -ForegroundColor $color
    Write-Host ''
}
