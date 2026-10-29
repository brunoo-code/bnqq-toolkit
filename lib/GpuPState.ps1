function Get-BnqqGpuPState {
    $smi = Get-BnqqNvidiaSmi
    if (-not $smi) {
        return [pscustomobject]@{ Supported = $false; PState = $null; GraphicsMHz = $null; MemoryMHz = $null }
    }

    $raw = (& $smi '--query-gpu=pstate,clocks.gr,clocks.mem' '--format=csv,noheader,nounits' '-i' '0' 2>$null) -join ''
    $parts = @($raw -split ',')
    if ($parts.Count -ge 3) {
        return [pscustomobject]@{
            Supported = $true
            PState = $parts[0].Trim()
            GraphicsMHz = [int]$parts[1].Trim()
            MemoryMHz = [int]$parts[2].Trim()
        }
    }

    return [pscustomobject]@{ Supported = $true; PState = $raw.Trim(); GraphicsMHz = $null; MemoryMHz = $null }
}

function Set-BnqqGpuPState {
    param([switch]$Quiet)

    $before = Get-BnqqGpuPState
    if (-not $before.Supported) {
        if (-not $Quiet) { Write-Bnqq 'GPU P-State: nvidia-smi indisponivel' 'WARN' }
        return $null
    }

    $smi = Get-BnqqNvidiaSmi
    & $smi -i 0 -pm 1 2>$null | Out-Null
    $locked = Set-BnqqGpuClockLock -Quiet
    $after = Get-BnqqGpuPState

    if (-not $Quiet) {
        Write-Bnqq ('GPU P-State: {0} -> {1}; clock {2} MHz' -f $before.PState, $after.PState, $after.GraphicsMHz) 'OK'
        Write-Bnqq 'GPU P-State: nvidia-smi trava clock maximo; P-State 0 nao tem API publica garantida' 'INFO'
    }
    return [pscustomobject]@{ Before = $before; After = $after; ClockLock = $locked }
}

function Clear-BnqqGpuPState {
    $null = Clear-BnqqGpuClockLock -Quiet
    return (Get-BnqqGpuPState)
}

function Show-BnqqGpuPState {
    $s = Get-BnqqGpuPState
    Write-Host ''
    Write-Host '  GPU P-STATE' -ForegroundColor Cyan
    if (-not $s.Supported) {
        Write-Host '    nvidia-smi indisponivel' -ForegroundColor Yellow
    }
    else {
        Write-Host ('    P-State     {0}' -f $s.PState) -ForegroundColor $(if ($s.PState -eq 'P0') { 'Green' } else { 'Yellow' })
        Write-Host ('    Clock       {0} MHz / memoria {1} MHz' -f $s.GraphicsMHz, $s.MemoryMHz) -ForegroundColor Gray
        Write-Host '    Comando     nvidia-smi -lgc max -pm 1; NVAPI/Inspector nao e baixado automaticamente' -ForegroundColor DarkGray
    }
    Write-Host ''
}
