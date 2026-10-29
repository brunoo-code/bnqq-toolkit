function Get-BnqqLatestHeavyQa {
    param([int]$MaxAgeHours = 24)

    $dir = Join-Path $script:BnqqRoot 'reports'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $file = Get-ChildItem -LiteralPath $dir -Filter 'heavyqa-*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $file) { return $null }

    try {
        $data = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $generated = [datetime]::Parse($data.Generated)
        $ageHours = ((Get-Date) - $generated).TotalHours
        return [pscustomobject]@{
            File = $file.FullName
            Generated = $generated
            AgeHours = [math]::Round($ageHours, 2)
            Verdict = $data.Verdict
            WheaCount = $data.WheaCount
            Minutes = $data.Minutes
            Fresh = ($ageHours -ge 0 -and $ageHours -le $MaxAgeHours)
            Passed = ($data.Verdict -eq 'PASS' -and [int]$data.WheaCount -eq 0 -and $ageHours -ge 0 -and $ageHours -le $MaxAgeHours)
        }
    }
    catch {
        return $null
    }
}

function Assert-BnqqHeavyQa {
    $cert = Get-BnqqLatestHeavyQa -MaxAgeHours 24
    if (-not $cert -or -not $cert.Passed) {
        throw 'Heavy QA obrigatorio: rode .\bnqq.ps1 heavyqa -HeavyMinutes 10 antes de habilitar IDLEDISABLE/COALTIME/PROCIR'
    }
}

function Test-BnqqHeavyQA {
    param(
        [ValidateRange(5, 30)][int]$Minutes = 10,
        [int]$Threads = 0,
        [int]$IdleTailSeconds = 30
    )

    if (-not (Test-BnqqAdmin)) { throw 'Heavy QA exige elevacao' }
    if (-not (Get-Command Test-BnqqStability -ErrorAction SilentlyContinue)) { throw 'Test-BnqqStability indisponivel' }

    $seconds = $Minutes * 60
    $reportDir = Join-Path $script:BnqqRoot 'reports'
    if (-not (Test-Path -LiteralPath $reportDir)) { New-Item -ItemType Directory -Force -Path $reportDir | Out-Null }
    $ioFile = Join-Path $env:TEMP ('BNQQ_HeavyQA_{0}.bin' -f $PID)
    $start = Get-Date
    $ioJob = $null

    $ioScript = {
        param($Path, $Seconds)
        $buffer = New-Object byte[] (16MB)
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            $deadline = (Get-Date).AddSeconds($Seconds)
            while ((Get-Date) -lt $deadline) {
                $stream.Position = 0
                $stream.Write($buffer, 0, $buffer.Length)
                $stream.Flush()
                $stream.Position = 0
                $read = New-Object byte[] 65536
                while ($stream.Read($read, 0, $read.Length) -gt 0) { }
            }
        }
        finally {
            $stream.Dispose()
            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Bnqq ('Heavy QA: {0} min de CPU + I/O + cauda idle de {1}s' -f $Minutes, $IdleTailSeconds) 'STEP'
    try {
        $ioJob = Start-Job -ScriptBlock $ioScript -ArgumentList $ioFile, ($seconds + 30)
        Test-BnqqStability -Minutes $Minutes -Threads $Threads -ReportDir $reportDir
    }
    finally {
        if ($ioJob) {
            Stop-Job -Job $ioJob -ErrorAction SilentlyContinue
            Remove-Job -Job $ioJob -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $ioFile -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds $IdleTailSeconds
    $whea = Get-BnqqWheaEvents -Since $start
    $wheaError = $whea.Error
    $wheaCount = if ($whea) { @($whea.Events).Count } else { 0 }
    $verdict = if ($wheaError) { 'INDETERMINATE' } elseif ($wheaCount -gt 0) { 'FAIL' } else { 'PASS' }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $file = Join-Path $reportDir ('heavyqa-{0}.json' -f $stamp)
    $payload = [pscustomobject]@{
        Generated = (Get-Date).ToString('o')
        Started = $start.ToString('o')
        Minutes = $Minutes
        Threads = $Threads
        IdleTailSeconds = $IdleTailSeconds
        WheaCount = $wheaCount
        WheaError = $wheaError
        WheaEvents = @($whea.Events | ForEach-Object { [pscustomobject]@{ Time = $_.TimeCreated.ToString('o'); Id = $_.Id; Message = $_.Message } })
        Verdict = $verdict
    }
    $payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $file -Encoding UTF8

    Write-Host ''
    Write-Host '  HEAVY QA' -ForegroundColor Cyan
    Write-Host ('    Duracao       {0} min + {1}s idle' -f $Minutes, $IdleTailSeconds) -ForegroundColor Gray
    Write-Host ('    WHEA          {0}' -f $wheaCount) -ForegroundColor $(if ($wheaCount) { 'Red' } else { 'Green' })
    Write-Host ('    Veredito      {0}' -f $verdict) -ForegroundColor $(if ($verdict -eq 'PASS') { 'Green' } else { 'Yellow' })
    Write-Host ('    Relatorio     {0}' -f $file) -ForegroundColor Gray
    Write-Host ''
    return $payload
}
