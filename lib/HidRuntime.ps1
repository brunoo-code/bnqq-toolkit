function Get-BnqqHidRuntimeStatus {
    $mousePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters'
    $kbdPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters'
    $mouseQueue = (Get-ItemProperty -LiteralPath $mousePath -Name MouseDataQueueSize -ErrorAction SilentlyContinue).MouseDataQueueSize
    $kbdQueue = (Get-ItemProperty -LiteralPath $kbdPath -Name KeyboardDataQueueSize -ErrorAction SilentlyContinue).KeyboardDataQueueSize

    $usb = @(Get-PnpDevice -Class USB -Status OK -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like 'PCI\*' } | ForEach-Object {
            $msi = Get-BnqqDeviceKey $_.InstanceId 'MessageSignaledInterruptProperties'
            $aff = Get-BnqqDeviceKey $_.InstanceId 'Affinity Policy'
            $m = Get-ItemProperty -LiteralPath $msi -ErrorAction SilentlyContinue
            $a = Get-ItemProperty -LiteralPath $aff -ErrorAction SilentlyContinue
            $mask = if ($a.AssignmentSetOverride) { (($a.AssignmentSetOverride | ForEach-Object { $_.ToString('X2') }) -join '') } else { '' }
            [pscustomobject]@{
                Device = $_.FriendlyName
                Msi = $m.MSISupported
                Priority = $m.DevicePriority
                Policy = $a.DevicePolicy
                Mask = $mask
            }
        })

    return [pscustomobject]@{
        MouseQueue = $mouseQueue
        KeyboardQueue = $kbdQueue
        UsbControllers = $usb
        QueueNote = '20 e o menor valor que mantemos como seguro para mouse 8 kHz; abaixo disso ha risco de perda'
    }
}

function Set-BnqqHidRuntime {
    param([ValidateRange(16, 64)][int]$QueueSize = 20)

    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para ajustar a pilha HID' }

    if ($QueueSize -lt 20) {
        Write-Bnqq ('HID: {0} e agressivo; mantendo 20 como piso seguro' -f $QueueSize) 'WARN'
        $QueueSize = 20
    }

    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters' 'MouseDataQueueSize' $QueueSize 'DWord'
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters' 'KeyboardDataQueueSize' $QueueSize 'DWord'
    Set-BnqqKeyboardResponse
    Set-BnqqUsbPowerSaving
    Set-BnqqUsb3LinkPowerManagement 0
    Set-BnqqUsbInputPriority

    Write-Bnqq ('HID: filas {0} pacotes; aceleracao off; USB sem suspensao' -f $QueueSize) 'OK'
    Write-Bnqq 'HID: mouclass/kbdclass sao drivers de boot; o novo valor de fila so vale no proximo boot' 'INFO'
    Write-Bnqq 'HID: MSI/prioridade e afinidade USB podem exigir reinicio do controlador; nao reiniciamos o dispositivo automaticamente' 'INFO'
}
