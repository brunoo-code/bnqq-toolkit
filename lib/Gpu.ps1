function Get-BnqqGpuInfo {
    return @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual' })
}

function Get-BnqqGpuVendor {
    $gpu = Get-BnqqGpuInfo | Select-Object -First 1
    if (-not $gpu) { return 'none' }
    if ($gpu.Name -match 'NVIDIA') { return 'nvidia' }
    if ($gpu.Name -match 'AMD|Radeon') { return 'amd' }
    if ($gpu.Name -match 'Intel') { return 'intel' }
    return 'unknown'
}

function Get-BnqqGpuDriverKeys {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    return @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })
}

function Get-BnqqNvidiaSmi {
    $cmd = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $fallback = 'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe'
    if (Test-Path -LiteralPath $fallback) { return $fallback }

    return $null
}

function Set-BnqqNvidiaProfile {
    $applied = 0

    foreach ($key in Get-BnqqGpuDriverKeys) {
        $desc = (Get-ItemProperty -LiteralPath $key.PSPath -Name DriverDesc -ErrorAction SilentlyContinue).DriverDesc
        if ($desc -notmatch 'NVIDIA') { continue }

        Set-BnqqReg $key.PSPath 'DisableDynamicPstate' 1

        $shader = Get-ItemProperty -LiteralPath $key.PSPath -Name ShaderCacheSize -ErrorAction SilentlyContinue
        if ($null -ne $shader.ShaderCacheSize) {
            Set-BnqqReg $key.PSPath 'ShaderCacheSize' ([uint32]::MaxValue)
            Write-Bnqq ('NVIDIA: shader cache unlimited em {0}' -f $key.PSChildName) 'OK'
        }

        $applied++
        Write-Bnqq ('NVIDIA: {0} com P-state fixo' -f $desc) 'OK'
    }

    $smi = Get-BnqqNvidiaSmi
    if ($smi) {
        & $smi -pm 1 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Bnqq 'nvidia-smi: persistence mode ativo' 'OK' }
        else { Write-Bnqq 'nvidia-smi: persistence mode nao suportado neste driver' 'INFO' }
    }

    if ($applied -eq 0) { Write-Bnqq 'Nenhum driver NVIDIA encontrado' 'INFO' }
}

function Set-BnqqAmdProfile {
    $applied = 0

    foreach ($key in Get-BnqqGpuDriverKeys) {
        $desc = (Get-ItemProperty -LiteralPath $key.PSPath -Name DriverDesc -ErrorAction SilentlyContinue).DriverDesc
        if ($desc -notmatch 'AMD|Radeon') { continue }

        Set-BnqqReg $key.PSPath 'EnableUlps' 0
        Set-BnqqReg $key.PSPath 'KMD_DeLagEnabled' 1
        Set-BnqqReg $key.PSPath 'PP_ThermalAutoThrottlingEnable' 0
        Set-BnqqReg $key.PSPath 'DisableDrmdmaPowerGating' 1

        $applied++
        Write-Bnqq ('AMD: {0} com ULPS off e Anti-Lag on' -f $desc) 'OK'
    }

    if ($applied -eq 0) { Write-Bnqq 'Nenhum driver AMD encontrado' 'INFO' }
}

function Set-BnqqGpuVendorProfile {
    switch (Get-BnqqGpuVendor) {
        'nvidia' { Set-BnqqNvidiaProfile }
        'amd'    { Set-BnqqAmdProfile }
        default  { Write-Bnqq 'GPU sem perfil de vendor aplicavel' 'INFO' }
    }
}
