function Set-BnqqUltimateAiOff {
    Set-BnqqReg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-BnqqReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    Set-BnqqReg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    Set-BnqqReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
    Set-BnqqReg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
    Set-BnqqReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableCopilot' 1
    Write-Bnqq 'Ultimate: Copilot e Recall bloqueados por politica' 'OK'
}

function Set-BnqqUltimateServices {
    param(
        [switch]$ForceSpooler,
        [switch]$DisableWindowsUpdate
    )

    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para desativar servicos' }

    $hasPrinter = @(Get-Printer -ErrorAction SilentlyContinue).Count -gt 0
    $targets = @('Fax', 'Spooler', 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc')
    if ($DisableWindowsUpdate) { $targets += 'wuauserv' }

    $store = @{}
    foreach ($name in $targets) {
        if ($name -eq 'Spooler' -and $hasPrinter -and -not $ForceSpooler) {
            Write-Bnqq 'Spooler mantido: impressora detectada (use -ForceSpooler para ignorar)' 'WARN'
            continue
        }

        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        $store[$name] = $svc.StartType.ToString()
        try {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
            Write-Bnqq ('Ultimate: servico desativado {0}' -f $name) 'OK'
        }
        catch {
            Write-Bnqq ('Ultimate: falha ao desativar {0}: {1}' -f $name, $_.Exception.Message) 'WARN'
        }
    }

    if ($store.Count -gt 0) {
        $dir = Join-Path $script:BnqqRoot 'backups'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $file = Join-Path $dir ('ultimate-services-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $store | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $file -Encoding UTF8
        Write-Bnqq ('Ultimate: estados anteriores em {0}' -f $file) 'INFO'
    }
}

function Set-BnqqUltimateMmcSS {
    $base = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\BNQQ_Esports'
    Set-BnqqReg $base 'Scheduling Category' 'High' 'String'
    Set-BnqqReg $base 'SFIO Priority' 'High' 'String'
    Set-BnqqReg $base 'GPU Priority' 8 'DWord'
    Set-BnqqReg $base 'Priority' 6 'DWord'
    Set-BnqqReg $base 'Clock Rate' 10000 'DWord'
    Write-Bnqq 'Ultimate: perfil MMCSS BNQQ_Esports criado' 'OK'
}

function Set-BnqqUltimateDesktopHeap {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para alterar SharedSection' }

    $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\SubSystems'
    $current = (Get-ItemProperty -LiteralPath $path -Name Windows -ErrorAction SilentlyContinue).Windows
    if (-not $current) { Write-Bnqq 'Ultimate: SharedSection indisponivel' 'WARN'; return }

    $new = [regex]::Replace($current, 'SharedSection=\d+,\d+,\d+', 'SharedSection=1024,20480,2048')
    if ($new -eq $current) { Write-Bnqq 'Ultimate: SharedSection ja esta no alvo' 'INFO'; return }
    Set-BnqqReg $path 'Windows' $new 'String'
    Write-Bnqq 'Ultimate: SharedSection=1024,20480,2048 (logoff/reboot)' 'OK'
}

function Set-BnqqUltimateVbsOff {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para VBS/DMA' }

    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0 'DWord'
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'RequirePlatformSecurityFeatures' 0 'DWord'
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0 'DWord'
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\DmaGuard' 'DeviceEnumerationPolicy' 0 'DWord'
    Write-Bnqq 'Ultimate: VBS/HVCI e Kernel DMA Protection desativados (reboot)' 'OK'
}

function Set-BnqqUltimate {
    param(
        [switch]$ForceSpooler,
        [switch]$DisableWindowsUpdate,
        [switch]$RemoveAppx,
        [switch]$DesktopHeap,
        [switch]$VbsOff
    )

    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para aplicar o Ultimate' }

    Set-BnqqUltimateAiOff
    Set-BnqqUltimateServices -ForceSpooler:$ForceSpooler -DisableWindowsUpdate:$DisableWindowsUpdate
    Set-BnqqUltimateMmcSS
    if ($RemoveAppx) { Set-BnqqDebloatAppx }
    if ($DesktopHeap) { Set-BnqqUltimateDesktopHeap }
    if ($VbsOff) { Set-BnqqUltimateVbsOff }
    Set-BnqqMeta 'UltimateApplied' $true
    Write-Bnqq 'Ultimate: faxina e perfis aplicados (reboot recomendado)' 'OK'
}

function Get-BnqqUltimateStatus {
    $filters = @()
    try { $filters = @(& fltmc filters 2>$null) } catch { }
    $wd = ($filters | Select-String -Pattern 'WdFilter' | Select-Object -First 1)
    $mm = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\BNQQ_Esports' -ErrorAction SilentlyContinue
    $heap = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\SubSystems' -Name Windows -ErrorAction SilentlyContinue).Windows
    $vbs = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name EnableVirtualizationBasedSecurity -ErrorAction SilentlyContinue).EnableVirtualizationBasedSecurity
    $dma = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DmaGuard' -Name DeviceEnumerationPolicy -ErrorAction SilentlyContinue).DeviceEnumerationPolicy
    $services = @{}
    foreach ($name in @('Fax', 'Spooler', 'wuauserv', 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc')) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) { $services[$name] = $svc.StartType.ToString() }
    }

    return [pscustomobject]@{
        WdFilterLoaded = [bool]$wd
        WdFilterNote = 'fltmc unload WdFilter nao e suportado/seguro; nao executado'
        Mmcss = $mm
        SharedSection = $heap
        Vbs = $vbs
        DmaGuard = $dma
        Services = $services
    }
}

function Show-BnqqUltimateStatus {
    param($Status)
    if (-not $Status) { $Status = Get-BnqqUltimateStatus }

    Write-Host ''
    Write-Host '  ULTIMATE / SUPER PACK' -ForegroundColor Cyan
    Write-Host ('    WdFilter     {0}' -f $(if ($Status.WdFilterLoaded) { 'carregado (nao descarregado)' } else { 'nao encontrado' })) -ForegroundColor Yellow
    Write-Host ('    MMCSS        {0}' -f $(if ($Status.Mmcss) { 'BNQQ_Esports presente' } else { 'ausente' })) -ForegroundColor $(if ($Status.Mmcss) { 'Green' } else { 'Yellow' })
    Write-Host ('    SharedSection {0}' -f $(if ($Status.SharedSection -match 'SharedSection=([^ ]+)') { $Matches[1] } else { 'indisponivel' })) -ForegroundColor Gray
    Write-Host ('    VBS / DMA    {0} / {1}' -f $Status.Vbs, $Status.DmaGuard) -ForegroundColor Gray
    foreach ($key in $Status.Services.Keys) {
        Write-Host ('    {0,-14} {1}' -f $key, $Status.Services[$key]) -ForegroundColor Gray
    }
    Write-Host '    WdFilter nao e descarregado: protecao em tempo real e boot safety' -ForegroundColor DarkGray
    Write-Host ''
}
