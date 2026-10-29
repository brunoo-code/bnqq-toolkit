$script:BnqqLicenseVersion = 'BNQQ-LICENSE-V1'
$script:BnqqLicensePublicKey = @'
<RSAKeyValue><Modulus>mBQmIjMf7HNR3/R0CHSGyT0Dxi1j0E43ylz7U1XAd1JzQGGBOmkB72K5dSlea5NJtNJp3mX3aiLZJuezWljC4uvuedP97DCBGBTj68v9A66KVKUVa0VXl9wsx5g7rqj43nXJCYsLnq6068l9m0ocRK7uT1TkyNpzjubpX8PcAkrefpxl3Qdqxjsl7NOze2LTOTfMrT0CAbfmJmjq/vdd1nb4b7jkA75IAv5jI1mXNYcjus+XJU0Bf2EcENbhsuRI0lXBYpMRPcs63i+OemLViOtFJBf4LG6WiSLIekE+0Afhe8s1zbZFyAOChjOepRtT3qtGs+UVtiZ+PHeKt7e5bQ==</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>
'@

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

function Get-BnqqLicensePath {
    return (Join-Path $script:BnqqRoot 'license.key')
}

function Test-BnqqLicense {
    param([string]$Path)

    if (-not $Path) { $Path = Get-BnqqLicensePath }
    $hwid = Get-BnqqHwid
    $result = [pscustomobject]@{
        Valid  = $false
        Hwid   = $hwid
        Reason = $null
        Path   = $Path
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        $result.Reason = 'license.key ausente'
        return $result
    }

    try {
        $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
        $version = ($lines | Where-Object { $_ -like 'BNQQ-LICENSE-*' } | Select-Object -First 1)
        $fileHwid = ($lines | Where-Object { $_ -like 'HWID=*' } | Select-Object -First 1) -replace '^HWID=', ''
        $signature = ($lines | Where-Object { $_ -like 'SIG=*' } | Select-Object -First 1) -replace '^SIG=', ''

        if (-not $version -or -not $fileHwid -or -not $signature) {
            $result.Reason = 'formato de licenca invalido'
            return $result
        }
        if ($version.Trim() -ne $script:BnqqLicenseVersion) {
            $result.Reason = 'versao de licenca invalida'
            return $result
        }
        if ($fileHwid.Trim().ToUpperInvariant() -ne $hwid) {
            $result.Reason = 'HWID nao corresponde a esta maquina'
            return $result
        }

        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
        $rsa.FromXmlString($script:BnqqLicensePublicKey)
        $data = [Text.Encoding]::UTF8.GetBytes(('{0}|{1}' -f $script:BnqqLicenseVersion, $hwid))
        $valid = $rsa.VerifyData($data, 'SHA256', [Convert]::FromBase64String($signature))
        $rsa.Dispose()

        if ($valid) {
            $result.Valid = $true
            return $result
        }

        $result.Reason = 'assinatura invalida'
        return $result
    }
    catch {
        $result.Reason = $_.Exception.Message
        return $result
    }
}

function Show-BnqqLicenseFailure {
    param($Status)

    Write-Host ''
    Write-Host '  LICENÇA INVÁLIDA' -ForegroundColor Red
    Write-Host ('    HWID        {0}' -f $Status.Hwid) -ForegroundColor Yellow
    Write-Host ('    Motivo      {0}' -f $Status.Reason) -ForegroundColor Gray
    Write-Host '    Envie o HWID acima ao desenvolvedor e coloque o license.key na pasta do BNQQ.' -ForegroundColor Gray
    Write-Host ''
}
