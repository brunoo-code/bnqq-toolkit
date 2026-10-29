function Get-BnqqEtwSnapshot {
    $rows = @(Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -ErrorAction SilentlyContinue)
    $total = $rows | Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
    if (-not $total -and $rows.Count -gt 0) {
        $dpc = ($rows | Measure-Object PercentDPCTime -Average).Average
        $isr = ($rows | Measure-Object PercentInterruptTime -Average).Average
        $irq = ($rows | Measure-Object InterruptsPersec -Sum).Sum
    }
    else {
        $dpc = if ($total) { $total.PercentDPCTime } else { 0 }
        $isr = if ($total) { $total.PercentInterruptTime } else { 0 }
        $irq = if ($total) { $total.InterruptsPersec } else { 0 }
    }

    $dwm = Get-Process -Name dwm -ErrorAction SilentlyContinue | Select-Object -First 1
    return [pscustomobject]@{
        Time = Get-Date
        DpcPercent = [double]$dpc
        IsrPercent = [double]$isr
        InterruptsPerSec = [double]$irq
        DwmCpu = if ($dwm) { [double]$dwm.CPU } else { $null }
        DwmWorkingSetMB = if ($dwm) { [math]::Round($dwm.WorkingSet64 / 1MB, 1) } else { $null }
    }
}

function Start-BnqqEtwMonitor {
    param(
        [ValidateRange(5, 120)][int]$Seconds = 10,
        [ValidateRange(250, 5000)][int]$IntervalMs = 500,
        [switch]$Wpr,
        [string]$WprFile
    )

    $samples = New-Object System.Collections.Generic.List[object]
    $end = (Get-Date).AddSeconds($Seconds)
    $previousDwm = $null
    $wprStarted = $false

    if ($Wpr) {
        if (-not (Test-BnqqAdmin)) {
            Write-Bnqq 'WPR exige elevacao; seguindo apenas com ETW/PDH' 'WARN'
            $Wpr = $false
        }
        else {
            if (-not $WprFile) {
                $dir = Join-Path $script:BnqqRoot 'reports'
                if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
                $WprFile = Join-Path $dir ('bnqq-wpr-{0}.etl' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
            }
            & wpr.exe -start CPU -filemode 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $wprStarted = $true
                Write-Bnqq ('WPR iniciado: {0}' -f $WprFile) 'OK'
            }
            else {
                Write-Bnqq 'WPR nao iniciou; seguindo com ETW/PDH' 'WARN'
            }
        }
    }

    Write-Bnqq ('ETW/PDH: amostrando DPC/ISR/DWM por {0}s' -f $Seconds) 'STEP'
    while ((Get-Date) -lt $end) {
        $s = Get-BnqqEtwSnapshot
        if ($previousDwm -ne $null -and $s.DwmCpu -ne $null) {
            $delta = $s.DwmCpu - $previousDwm
            $s | Add-Member -NotePropertyName DwmCpuDelta -NotePropertyValue $delta -Force
        }
        else {
            $s | Add-Member -NotePropertyName DwmCpuDelta -NotePropertyValue $null -Force
        }
        $previousDwm = $s.DwmCpu
        $samples.Add($s)
        Start-Sleep -Milliseconds $IntervalMs
    }

    if ($wprStarted) {
        & wpr.exe -stop $WprFile 2>$null | Out-Null
        if (Test-Path -LiteralPath $WprFile) { Write-Bnqq ('WPR salvo: {0}' -f $WprFile) 'OK' }
        else { Write-Bnqq 'WPR: ETL nao foi gerado' 'WARN' }
    }

    if ($samples.Count -eq 0) {
        Write-Bnqq 'ETW/PDH: nenhuma amostra' 'WARN'
        return $null
    }

    $dpcAvg = ($samples | Measure-Object DpcPercent -Average).Average
    $dpcMax = ($samples | Measure-Object DpcPercent -Maximum).Maximum
    $isrAvg = ($samples | Measure-Object IsrPercent -Average).Average
    $isrMax = ($samples | Measure-Object IsrPercent -Maximum).Maximum
    $irqAvg = ($samples | Measure-Object InterruptsPerSec -Average).Average
    $dwmDeltas = @($samples | Where-Object { $null -ne $_.DwmCpuDelta } | ForEach-Object { $_.DwmCpuDelta })
    $dwmAvg = if ($dwmDeltas.Count -gt 0) { ($dwmDeltas | Measure-Object -Average).Average } else { $null }
    $dwmMax = if ($dwmDeltas.Count -gt 0) { ($dwmDeltas | Measure-Object -Maximum).Maximum } else { $null }

    $result = [pscustomobject]@{
        Seconds = $Seconds
        Samples = $samples.Count
        DpcAvg = [math]::Round($dpcAvg, 2)
        DpcMax = [math]::Round($dpcMax, 2)
        IsrAvg = [math]::Round($isrAvg, 2)
        IsrMax = [math]::Round($isrMax, 2)
        InterruptsAvg = [math]::Round($irqAvg, 0)
        DwmCpuAvgSec = if ($dwmAvg -ne $null) { [math]::Round($dwmAvg, 3) } else { $null }
        DwmCpuMaxSec = if ($dwmMax -ne $null) { [math]::Round($dwmMax, 3) } else { $null }
        DwmWorkingSetMB = $samples[$samples.Count - 1].DwmWorkingSetMB
        WprFile = if ($wprStarted) { $WprFile } else { $null }
    }

    $dir = Join-Path $script:BnqqRoot 'reports'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $file = Join-Path $dir ('etw-monitor-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $file -Encoding UTF8
    Write-Bnqq ('ETW/PDH salvo: {0}' -f $file) 'INFO'

    Write-Host ''
    Write-Host '  ETW / PDH MONITOR' -ForegroundColor Cyan
    Write-Host ('    Amostras       {0} em {1}s' -f $result.Samples, $Seconds) -ForegroundColor Gray
    Write-Host ('    DPC            avg {0}% · max {1}%' -f $result.DpcAvg, $result.DpcMax) -ForegroundColor Gray
    Write-Host ('    ISR            avg {0}% · max {1}%' -f $result.IsrAvg, $result.IsrMax) -ForegroundColor Gray
    Write-Host ('    Interrupcoes   {0}/s' -f $result.InterruptsAvg) -ForegroundColor Gray
    Write-Host ('    DWM CPU        avg {0}s · max {1}s por amostra' -f $result.DwmCpuAvgSec, $result.DwmCpuMaxSec) -ForegroundColor Gray
    Write-Host ('    DWM working    {0} MB' -f $result.DwmWorkingSetMB) -ForegroundColor Gray
    Write-Host '    Fonte: contadores ETW/PDH do kernel e DWM; nao e um ETL completo do WPR' -ForegroundColor DarkGray
    Write-Host ''
    return $result
}

function Show-BnqqEtwStatus {
    $s = Get-BnqqEtwSnapshot
    Write-Host ''
    Write-Host '  ETW / PDH' -ForegroundColor Cyan
    Write-Host ('    DPC {0}% · ISR {1}% · IRQ {2}/s' -f $s.DpcPercent, $s.IsrPercent, $s.InterruptsPerSec) -ForegroundColor Gray
    Write-Host ('    DWM CPU {0}s · working set {1} MB' -f $s.DwmCpu, $s.DwmWorkingSetMB) -ForegroundColor Gray
    Write-Host '    Use `etw -EtwSeconds 15` para amostrar durante o jogo' -ForegroundColor DarkGray
    Write-Host ''
}
