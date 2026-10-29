function Get-BnqqHwid {
    $uuid = $null
    $processorId = $null

    try {
        $cs = Get-WmiObject -Class Win32_ComputerSystemProduct -ErrorAction Stop
        $uuid = $cs.UUID
    }
    catch {
        $cs = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
        $uuid = $cs.UUID
    }

    try {
        $cpu = Get-WmiObject -Class Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $processorId = $cpu.ProcessorId
    }
    catch {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        $processorId = $cpu.ProcessorId
    }

    $raw = '{0}|{1}' -f (([string]$uuid).Trim().ToUpperInvariant()), (([string]$processorId).Trim().ToUpperInvariant())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw)))).Replace('-', '').ToUpperInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Test-BnqqAllowlist {
    param([Parameter(Mandatory = $true)][string]$Url)

    $hwid = Get-BnqqHwid
    $result = [pscustomobject]@{
        Valid  = $false
        Hwid   = $hwid
        Reason = $null
        Url    = $Url
    }

    if ([string]::IsNullOrWhiteSpace($Url) -or $Url -eq 'COLOQUE_SEU_LINK_AQUI') {
        $result.Reason = 'Allowlist URL nao configurada'
        return $result
    }
    if ($Url -notmatch '^https?://') {
        $result.Reason = 'Allowlist URL precisa ser http(s) Raw'
        return $result
    }

    try {
        $text = [string](Invoke-RestMethod -Uri $Url -Method Get -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop)
        $normalized = ($text.ToUpperInvariant() -replace '[^0-9A-F]', ' ')
        $tokens = @($normalized -split '\s+' | Where-Object { $_ -match '^[0-9A-F]{64}$' })
        if ($tokens -contains $hwid) {
            $result.Valid = $true
            return $result
        }
        $result.Reason = 'HWID nao encontrado na allowlist'
        return $result
    }
    catch {
        $result.Reason = 'Falha ao consultar allowlist: ' + $_.Exception.Message
        return $result
    }
}

function Show-BnqqAllowlistFailure {
    param($Status)

    Write-Host ''
    Write-Host '  NAO AUTORIZADO' -ForegroundColor Red
    Write-Host ('    HWID        {0}' -f $Status.Hwid) -ForegroundColor Yellow
    Write-Host ('    Motivo      {0}' -f $Status.Reason) -ForegroundColor Gray
    Write-Host '    Adicione este HWID na allowlist e abra o BNQQ novamente.' -ForegroundColor Gray
    Write-Host ''
    if ([Environment]::UserInteractive) {
        try { Read-Host 'Pressione Enter para fechar' | Out-Null } catch { }
    }
}
