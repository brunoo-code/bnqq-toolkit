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

function Get-BnqqHdcpStatus {
    foreach ($key in Get-BnqqGpuDriverKeys) {
        $desc = (Get-ItemProperty -LiteralPath $key.PSPath -Name DriverDesc -ErrorAction SilentlyContinue).DriverDesc
        if ($desc -notmatch 'NVIDIA') { continue }

        $reg = Get-Item -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        $values = @()
        if ($reg) {
            $values = @($reg.GetValueNames() | Where-Object { $_ -match '(?i)hdcp' } | ForEach-Object {
                [pscustomobject]@{
                    Name  = $_
                    Value = $reg.GetValue($_, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                }
            })
        }

        $status = if ($values.Count -gt 0) { 'registro presente; desativacao nao suportada' } else { 'sem controle HDCP suportado' }
        return [pscustomobject]@{
            Controllable = $false
            Adapter      = $desc
            Status       = $status
            Values       = $values
            Action       = 'Nao alterado: NVIDIA nao expoe API/registro publico para desativar HDCP'
        }
    }

    return [pscustomobject]@{
        Controllable = $false
        Adapter      = $null
        Status       = 'adaptador NVIDIA nao localizado'
        Values       = @()
        Action       = 'Nada a alterar'
    }
}

function Get-BnqqNvidiaSmi {
    $cmd = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $fallback = 'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe'
    if (Test-Path -LiteralPath $fallback) { return $fallback }

    return $null
}

function Get-BnqqGpuMaxClock {
    $smi = Get-BnqqNvidiaSmi
    if (-not $smi) { return $null }

    $raw = & $smi '--query-gpu=clocks.max.graphics' '--format=csv,noheader,nounits' '-i' '0' 2>$null
    $value = ($raw -join '').Trim()
    $max = 0
    if ([int]::TryParse($value, [ref]$max) -and $max -ge 500) { return $max }
    return $null
}

function Set-BnqqGpuClockLock {
    param([switch]$Quiet)

    $smi = Get-BnqqNvidiaSmi
    if (-not $smi) { return $false }

    $max = Get-BnqqGpuMaxClock
    if (-not $max) {
        if (-not $Quiet) { Write-Bnqq 'GPU: clock maximo indisponivel no nvidia-smi' 'WARN' }
        return $false
    }

    $output = & $smi '-i' '0' '-lgc' "$max,$max" 2>&1
    if ($LASTEXITCODE -eq 0) {
        if (-not $Quiet) { Write-Bnqq ('GPU: clock travado em {0} MHz' -f $max) 'OK' }
        return $true
    }

    if (-not $Quiet) { Write-Bnqq ('GPU: falha ao travar clock: {0}' -f (($output -join ' ').Trim())) 'WARN' }
    return $false
}

function Clear-BnqqGpuClockLock {
    param([switch]$Quiet)

    $smi = Get-BnqqNvidiaSmi
    if (-not $smi) { return $false }

    $output = & $smi '-i' '0' '-rgc' 2>&1
    if ($LASTEXITCODE -eq 0) {
        if (-not $Quiet) { Write-Bnqq 'GPU: clock liberado (nvidia-smi -rgc)' 'OK' }
        return $true
    }

    if (-not $Quiet) { Write-Bnqq ('GPU: falha ao liberar clock: {0}' -f (($output -join ' ').Trim())) 'WARN' }
    return $false
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
