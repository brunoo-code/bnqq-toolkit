function Get-BnqqSecurityPreflight {
    $secureBoot = $null
    try { $secureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { $secureBoot = $null }

    $tpm = $null
    try {
        $t = Get-Tpm -ErrorAction Stop
        $tpm = [pscustomobject]@{ Present = [bool]$t.TpmPresent; Ready = [bool]$t.TpmReady }
    }
    catch { $tpm = $null }

    $dg = $null
    try {
        $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop
    }
    catch { }

    $vgc = Get-Service -Name vgc -ErrorAction SilentlyContinue
    $vgk = Get-Service -Name vgk -ErrorAction SilentlyContinue
    $vbsRunning = $false
    $hvciRunning = $false
    if ($dg) {
        $vbsRunning = ([int]$dg.VirtualizationBasedSecurityStatus -eq 2)
        $hvciRunning = (@($dg.SecurityServicesRunning) -contains 2)
    }

    $tpmOk = $tpm -and $tpm.Present -and $tpm.Ready
    $antiCheat = [bool]($vgc -or $vgk)
    $ready = ($secureBoot -eq $true) -and $tpmOk -and $vbsRunning -and $hvciRunning

    return [pscustomobject]@{
        SecureBoot = $secureBoot
        Tpm = $tpm
        TpmOk = [bool]$tpmOk
        VbsRunning = $vbsRunning
        HvciRunning = $hvciRunning
        Hypervisor = if ($dg) { $dg.VirtualizationBasedSecurityStatus } else { $null }
        VanguardInstalled = $antiCheat
        ReadyForVanguard = $ready
        Note = 'Secure Boot + TPM pronto + VBS + HVCI; nenhuma dessas checagens e falsificada'
    }
}

function Show-BnqqSecurityPreflight {
    param($Status)
    if (-not $Status) { $Status = Get-BnqqSecurityPreflight }

    Write-Host ''
    Write-Host '  PREFLIGHT DE SEGURANCA' -ForegroundColor Cyan
    Write-Host ('    Secure Boot  {0}' -f $(if ($Status.SecureBoot -eq $true) { 'ativo' } elseif ($Status.SecureBoot -eq $false) { 'desativado' } else { 'indeterminado (UAC/admin)' })) -ForegroundColor $(if ($Status.SecureBoot -eq $true) { 'Green' } else { 'Yellow' })
    Write-Host ('    TPM          {0}' -f $(if ($Status.Tpm) { if ($Status.Tpm.Ready) { 'presente e pronto' } else { 'presente, nao pronto' } } else { 'indeterminado (UAC/admin)' })) -ForegroundColor $(if ($Status.TpmOk) { 'Green' } else { 'Yellow' })
    Write-Host ('    VBS runtime  {0}' -f $(if ($Status.VbsRunning) { 'rodando' } else { 'nao rodando' })) -ForegroundColor $(if ($Status.VbsRunning) { 'Green' } else { 'Yellow' })
    Write-Host ('    HVCI         {0}' -f $(if ($Status.HvciRunning) { 'rodando' } else { 'nao rodando' })) -ForegroundColor $(if ($Status.HvciRunning) { 'Green' } else { 'Yellow' })
    Write-Host ('    Vanguard     {0}' -f $(if ($Status.VanguardInstalled) { 'detectado' } else { 'nao detectado' })) -ForegroundColor Gray
    Write-Host ('    Conformidade  {0}' -f $(if ($Status.ReadyForVanguard) { 'PRONTA' } else { 'REVISAR' })) -ForegroundColor $(if ($Status.ReadyForVanguard) { 'Green' } else { 'Red' })
    Write-Host '    Nao ha bypass: se VBS/HVCI estiverem off, o perfil valorant deve ser bloqueado' -ForegroundColor DarkGray
    Write-Host ''
}

function Test-BnqqSecurityPreflight {
    return (Get-BnqqSecurityPreflight)
}
