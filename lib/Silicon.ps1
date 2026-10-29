function Get-BnqqSiliconMitigationStatus {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    $override = (Get-ItemProperty -LiteralPath $base -Name FeatureSettingsOverride -ErrorAction SilentlyContinue).FeatureSettingsOverride
    $mask = (Get-ItemProperty -LiteralPath $base -Name FeatureSettingsOverrideMask -ErrorAction SilentlyContinue).FeatureSettingsOverrideMask
    $feature = (Get-ItemProperty -LiteralPath $base -Name FeatureSettings -ErrorAction SilentlyContinue).FeatureSettings
    $vbs = $null
    try { $vbs = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop } catch { }

    return [pscustomobject]@{
        FeatureSettingsOverride = $override
        FeatureSettingsOverrideMask = $mask
        FeatureSettings = $feature
        VbsStatus = if ($vbs) { $vbs.VirtualizationBasedSecurityStatus } else { $null }
        HvciRunning = if ($vbs) { @($vbs.SecurityServicesRunning) -contains 2 } else { $false }
        Note = 'FeatureSettingsOverride/Mask sao politicas do Windows; nao alteram microcodigo nem todas as mitigacoes'
    }
}

function Set-BnqqSiliconMitigations {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para alterar mitigacoes' }

    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    Set-BnqqReg $base 'FeatureSettingsOverride' 3 'DWord'
    Set-BnqqReg $base 'FeatureSettingsOverrideMask' 3 'DWord'
    Write-Bnqq 'Silicon: FeatureSettingsOverride/Mask=3; reboot necessario' 'OK'
    Write-Bnqq 'Silicon: isso reduz mitigacoes do Windows, nao garante Retbleed/microcodigo off e aumenta risco de seguranca' 'WARN'
    return $true
}

function Get-BnqqNetworkModerationStatus {
    $rows = @()
    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $prop = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue |
            Where-Object { $_.RegistryKeyword -eq '*InterruptModeration' -or $_.DisplayName -match 'Interrupt Moderation|Modera..o de Interrup' } |
            Select-Object -First 1
        $rows += [pscustomobject]@{
            Name = $adapter.Name
            Driver = $adapter.InterfaceDescription
            DisplayValue = if ($prop) { $prop.DisplayValue } else { 'nao exposto' }
            RegistryValue = if ($prop) { $prop.RegistryValue } else { $null }
        }
    }
    return $rows
}

function Set-BnqqNetworkModerationOff {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para alterar Interrupt Moderation' }

    $changed = 0
    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $prop = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue |
            Where-Object { $_.RegistryKeyword -eq '*InterruptModeration' } | Select-Object -First 1
        if (-not $prop) {
            Write-Bnqq ('NIC: {0} nao expoe Interrupt Moderation' -f $adapter.Name) 'INFO'
            continue
        }
        if ($prop.RegistryValue -eq '0') {
            Write-Bnqq ('NIC: {0} ja esta Disabled' -f $adapter.Name) 'INFO'
            continue
        }
        try {
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword '*InterruptModeration' -RegistryValue 0 -ErrorAction Stop | Out-Null
            Write-Bnqq ('NIC: Interrupt Moderation Disabled em {0}' -f $adapter.Name) 'OK'
            $changed++
        }
        catch {
            Write-Bnqq ('NIC: falha em {0}: {1}' -f $adapter.Name, $_.Exception.Message) 'WARN'
        }
    }
    Write-Bnqq ('NIC: {0} adaptador(es) alterado(s)' -f $changed) 'STEP'
}

function Get-BnqqSiliconTools {
    $inspector = Get-Command nvidiaProfileInspector.exe -ErrorAction SilentlyContinue
    $ryzen = Get-Command ryzenmaster.exe -ErrorAction SilentlyContinue
    $ryzenAdj = Get-Command ryzenadj.exe -ErrorAction SilentlyContinue
    $xtu = Get-Command IntelXTU.exe -ErrorAction SilentlyContinue
    $throttle = Get-Command ThrottleStop.exe -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        NvidiaInspector = if ($inspector) { $inspector.Source } else { $null }
        RyzenMaster = if ($ryzen) { $ryzen.Source } else { $null }
        RyzenAdj = if ($ryzenAdj) { $ryzenAdj.Source } else { $null }
        IntelXTU = if ($xtu) { $xtu.Source } else { $null }
        ThrottleStop = if ($throttle) { $throttle.Source } else { $null }
    }
}

function Set-BnqqSilicon {
    param(
        [switch]$DisableMitigations,
        [switch]$NvidiaProfile,
        [switch]$Undervolt
    )

    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para aplicar Silicon' }

    Set-BnqqNetworkModerationOff
    if ($DisableMitigations) { Set-BnqqSiliconMitigations | Out-Null }
    else { Write-Bnqq 'Silicon: mitigacoes nao alteradas (use -DisableMitigations explicitamente)' 'INFO' }

    $tools = Get-BnqqSiliconTools
    if ($NvidiaProfile) {
        if ($tools.NvidiaInspector) {
            Write-Bnqq 'NVIDIA Profile Inspector encontrado, mas nao possui CLI estavel; nenhuma flag foi injetada' 'WARN'
        }
        else {
            Write-Bnqq 'NVIDIA Profile Inspector ausente; Maximum Pre-rendered Frames/Threaded Optimization nao foram alterados' 'WARN'
        }
    }

    if ($Undervolt) {
        if ($tools.RyzenMaster -or $tools.RyzenAdj) {
            Write-Bnqq 'Ferramenta AMD encontrada, mas o perfil Curve Optimizer exige comando/versao especificos; nao executado as cegas' 'WARN'
        }
        elseif ($tools.IntelXTU -or $tools.ThrottleStop) {
            Write-Bnqq 'Ferramenta Intel encontrada, mas nao ha CLI universal para undervolt; nao executado as cegas' 'WARN'
        }
        else {
            Write-Bnqq 'Nenhuma ferramenta AMD/Intel CLI encontrada; undervolt nao aplicado' 'WARN'
        }
    }
}

function Show-BnqqSiliconStatus {
    $mit = Get-BnqqSiliconMitigationStatus
    $nic = @(Get-BnqqNetworkModerationStatus)
    $tools = Get-BnqqSiliconTools
    $gpu = Get-BnqqGpuPState

    Write-Host ''
    Write-Host '  SILICON / MITIGACOES / NIC' -ForegroundColor Cyan
    Write-Host ('    Mitigacoes  override={0} mask={1} feature={2}' -f $mit.FeatureSettingsOverride, $mit.FeatureSettingsOverrideMask, $mit.FeatureSettings) -ForegroundColor Gray
    Write-Host ('    VBS/HVCI    status={0} hvci={1}' -f $mit.VbsStatus, $mit.HvciRunning) -ForegroundColor Gray
    foreach ($row in $nic) {
        Write-Host ('    NIC         {0}: {1}' -f $row.Name, $row.DisplayValue) -ForegroundColor Gray
    }
    Write-Host ('    GPU         P-State={0} clock={1} MHz' -f $gpu.PState, $gpu.GraphicsMHz) -ForegroundColor Gray
    Write-Host ('    Tools       Inspector={0} RyzenMaster={1} RyzenAdj={2} XTU={3} ThrottleStop={4}' -f [bool]$tools.NvidiaInspector, [bool]$tools.RyzenMaster, [bool]$tools.RyzenAdj, [bool]$tools.IntelXTU, [bool]$tools.ThrottleStop) -ForegroundColor Gray
    Write-Host '    Sem bypass de anti-cheat; ferramentas ausentes nao sao baixadas automaticamente' -ForegroundColor DarkGray
    Write-Host ''
}
