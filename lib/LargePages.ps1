function Get-BnqqLargePageStatus {
    $text = ''
    try { $text = (& whoami.exe /priv 2>$null) -join "`n" } catch { }
    $line = ($text -split "`r?`n" | Where-Object { $_ -match 'SeLockMemoryPrivilege' } | Select-Object -First 1)
    $enabled = $false
    if ($line -match 'Enabled') { $enabled = $true }
    $present = [bool]$line

    return [pscustomobject]@{
        Privilege = 'SeLockMemoryPrivilege'
        Present = $present
        Enabled = $enabled
        Account = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Note = 'Privilegio permite lock de paginas; o jogo ainda precisa solicitar MEM_LARGE_PAGES'
    }
}

function Set-BnqqLargePagePrivilege {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para conceder SeLockMemoryPrivilege' }

    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $cfg = Join-Path $env:TEMP ('bnqq-secedit-{0}.inf' -f (Get-Date -Format 'yyyyMMddHHmmss'))
    $db = Join-Path $env:TEMP ('bnqq-secedit-{0}.sdb' -f (Get-Date -Format 'yyyyMMddHHmmss'))

    & secedit /export /cfg $cfg /areas SECURITYPOLICY 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $cfg)) {
        Write-Bnqq 'Large Pages: secedit export falhou' 'WARN'
        return $false
    }

    try {
        $lines = @(Get-Content -LiteralPath $cfg -Encoding Unicode)
        $index = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*SeLockMemoryPrivilege\s*=') { $index = $i; break }
        }

        $entry = '*{0}' -f $sid
        if ($index -ge 0) {
            if ($lines[$index] -notmatch [regex]::Escape($sid)) {
                $lines[$index] = ($lines[$index].TrimEnd() + ',' + $entry)
            }
        }
        else {
            $section = -1
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^\s*\[Privilege Rights\]\s*$') { $section = $i; break }
            }
            if ($section -lt 0) {
                $lines += ''
                $lines += '[Privilege Rights]'
                $lines += ('SeLockMemoryPrivilege = ' + $entry)
            }
            else {
                $lines = @($lines[0..$section]) + @('SeLockMemoryPrivilege = ' + $entry) + @($lines[($section + 1)..($lines.Count - 1)])
            }
        }

        $lines | Set-Content -LiteralPath $cfg -Encoding Unicode
        & secedit /configure /db $db /cfg $cfg /areas SECURITYPOLICY /quiet 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Bnqq 'Large Pages: SeLockMemoryPrivilege concedido; requer logoff/reboot' 'OK'
            return $true
        }
        Write-Bnqq 'Large Pages: secedit configure falhou' 'WARN'
        return $false
    }
    catch {
        Write-Bnqq ('Large Pages: falha: {0}' -f $_.Exception.Message) 'WARN'
        return $false
    }
    finally {
        Remove-Item -LiteralPath $cfg, $db -Force -ErrorAction SilentlyContinue
    }
}

function Show-BnqqLargePageStatus {
    $s = Get-BnqqLargePageStatus
    Write-Host ''
    Write-Host '  LARGE PAGES / 2 MB' -ForegroundColor Cyan
    Write-Host ('    Conta       {0}' -f $s.Account) -ForegroundColor Gray
    Write-Host ('    Privilegio  SeLockMemoryPrivilege present={0} enabled={1}' -f $s.Present, $s.Enabled) -ForegroundColor $(if ($s.Enabled) { 'Green' } else { 'Yellow' })
    Write-Host '    Efeito      o jogo precisa chamar VirtualAlloc(MEM_LARGE_PAGES); o Windows nao forca isso' -ForegroundColor DarkGray
    Write-Host ''
}
