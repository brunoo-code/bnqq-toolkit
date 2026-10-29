#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [ValidateRange(1, 10)][int]$Runs = 3,
    [ValidateRange(10, 300)][int]$Seconds = 60,
    [ValidateRange(0, 30)][int]$SkipSeconds = 5
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$bnqq = Join-Path $root 'bnqq.ps1'
$reports = Join-Path $root 'reports'
if (-not (Test-Path -LiteralPath $reports)) { New-Item -ItemType Directory -Force -Path $reports | Out-Null }

if (-not (Get-Process -Name 'cs2' -ErrorAction SilentlyContinue)) {
    throw 'CS2 nao esta aberto'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcript = Join-Path $reports ('autobench-{0}.log' -f $stamp)
Start-Transcript -LiteralPath $transcript -Force | Out-Null

$results = @()
try {
    for ($i = 1; $i -le $Runs; $i++) {
        $before = @(Get-ChildItem -LiteralPath $reports -Filter 'framebench-*.json' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        Write-Host ('AUTOBENCH: execucao {0}/{1}' -f $i, $Runs) -ForegroundColor Cyan
        & $bnqq framebench -FrameSeconds $Seconds -FrameSkip $SkipSeconds -NoElevate
        if ($LASTEXITCODE -ne 0) { throw ('framebench falhou na execucao {0}' -f $i) }
        $after = @(Get-ChildItem -LiteralPath $reports -Filter 'framebench-*.json' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        $new = @($after | Where-Object { $before -notcontains $_ })
        if ($new.Count -eq 0) { throw ('framebench nao gerou JSON na execucao {0}' -f $i) }
        $json = Get-Content -LiteralPath $new[-1] -Raw -Encoding UTF8 | ConvertFrom-Json
        $results += [pscustomobject]@{
            Run = $i
            File = $new[-1]
            Frames = $json.Frames
            AvgFps = $json.AvgFps
            Low1Fps = $json.Low1Fps
            Low01Fps = $json.Low01Fps
            MaxMs = $json.MaxMs
            JitterMs = $json.JitterMs
        }
        Start-Sleep -Seconds 2
    }

    $summary = [pscustomobject]@{
        Generated = (Get-Date).ToString('o')
        Runs = $Runs
        Seconds = $Seconds
        SkipSeconds = $SkipSeconds
        Results = $results
        AvgLow1 = [math]::Round((($results | Measure-Object Low1Fps -Average).Average), 2)
        AvgLow01 = [math]::Round((($results | Measure-Object Low01Fps -Average).Average), 2)
        WorstMaxMs = [math]::Round((($results | Measure-Object MaxMs -Maximum).Maximum), 3)
        AvgJitterMs = [math]::Round((($results | Measure-Object JitterMs -Average).Average), 3)
    }
    $summaryFile = Join-Path $reports ('autobench-{0}.json' -f $stamp)
    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryFile -Encoding UTF8

    Write-Host ''
    Write-Host '  AUTOBENCH SUMMARY' -ForegroundColor Cyan
    $results | Format-Table Run, AvgFps, Low1Fps, Low01Fps, MaxMs, JitterMs -AutoSize
    Write-Host ('  Media 1% low: {0} FPS' -f $summary.AvgLow1) -ForegroundColor Yellow
    Write-Host ('  Media 0.1% low: {0} FPS' -f $summary.AvgLow01) -ForegroundColor Yellow
    Write-Host ('  Pior max: {0} ms | Jitter medio: {1} ms' -f $summary.WorstMaxMs, $summary.AvgJitterMs) -ForegroundColor Gray
    Write-Host ('  Summary: {0}' -f $summaryFile) -ForegroundColor Gray
    Write-Host ''
}
finally {
    Stop-Transcript | Out-Null
}
