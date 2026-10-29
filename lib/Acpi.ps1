function Get-BnqqAcpiTimerStatus {
    $usePlatformClock = 'indisponivel'
    $tscSync = 'indisponivel'
    $dynamicTick = 'nao definido'
    try {
        $bcd = @(& bcdedit /enum '{current}' 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $text = $bcd -join "`n"
            if ($text -match '(?im)^\s*useplatformclock\s+(\S+)') { $usePlatformClock = $Matches[1] }
            if ($text -match '(?im)^\s*tscsyncpolicy\s+(\S+)') { $tscSync = $Matches[1] }
            if ($text -match '(?im)^\s*disabledynamictick\s+(\S+)') { $dynamicTick = $Matches[1] }
        }
    }
    catch { }

    $hpet = @(Get-PnpDevice -Class System -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match 'High Precision|HPET' })

    return [pscustomobject]@{
        UsePlatformClock = $usePlatformClock
        TscSyncPolicy    = $tscSync
        DynamicTick      = $dynamicTick
        HpetDevices      = @($hpet | Select-Object FriendlyName, Status, InstanceId)
        TscSelected      = ($usePlatformClock -match '^No$')
        Note             = 'Windows escolhe TSC com useplatformclock=No; a tabela ACPI nao e editada'
    }
}

function Set-BnqqAcpiTimer {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para configurar o timer ACPI' }

    & bcdedit /set useplatformclock No 2>$null | Out-Null
    $clockOk = ($LASTEXITCODE -eq 0)
    & bcdedit /set tscsyncpolicy Enhanced 2>$null | Out-Null
    $syncOk = ($LASTEXITCODE -eq 0)

    if ($clockOk -and $syncOk) {
        Write-Bnqq 'ACPI/TSC: useplatformclock=No, tscsyncpolicy=Enhanced (reboot)' 'OK'
    }
    else {
        Write-Bnqq 'ACPI/TSC: falha ao gravar BCD' 'WARN'
    }
    Write-Bnqq 'ACPI: tabela HPET do firmware nao foi alterada; bypass de tabela nao e suportado' 'INFO'
}

function Show-BnqqAcpiStatus {
    param($Status)
    if (-not $Status) { $Status = Get-BnqqAcpiTimerStatus }

    Write-Host ''
    Write-Host '  ACPI / HPET / TSC' -ForegroundColor Cyan
    Write-Host ('    useplatformclock   {0}  [{1}]' -f $Status.UsePlatformClock, $(if ($Status.TscSelected) { 'TSC' } else { 'revisar' })) -ForegroundColor $(if ($Status.TscSelected) { 'Green' } else { 'Yellow' })
    Write-Host ('    tscsyncpolicy      {0}' -f $Status.TscSyncPolicy) -ForegroundColor Gray
    Write-Host ('    disabledynamictick {0}' -f $Status.DynamicTick) -ForegroundColor Gray
    if ($Status.HpetDevices.Count -gt 0) {
        foreach ($h in $Status.HpetDevices) {
            Write-Host ('    HPET               {0}  {1}' -f $h.FriendlyName, $h.Status) -ForegroundColor Gray
        }
    }
    else {
        Write-Host '    HPET               nao exposto por PnP' -ForegroundColor Gray
    }
    Write-Host '    A tabela ACPI nao e editada; o caminho suportado e TSC via BCD' -ForegroundColor DarkGray
    Write-Host ''
}
