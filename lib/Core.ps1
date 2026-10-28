$ErrorActionPreference = 'Continue'

$script:BnqqState = @{
    LogFile = $null
    Backup  = @{}
    Meta    = @{}
}

function Test-BnqqAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-BnqqElevation {
    param(
        [string]$ScriptPath,
        [string[]]$ScriptArgs = @()
    )

    if (Test-BnqqAdmin) { return }

    $shell = (Get-Process -Id $PID).Path
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$ScriptPath`"") + $ScriptArgs
    Start-Process -FilePath $shell -ArgumentList $argList -Verb RunAs
    exit 0
}

function Start-BnqqLog {
    param([string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    }

    $name = 'bnqq-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    $script:BnqqState.LogFile = Join-Path $Directory $name
    Set-Content -LiteralPath $script:BnqqState.LogFile -Value '' -Encoding UTF8
    return $script:BnqqState.LogFile
}

function Write-Bnqq {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERR', 'STEP')]
        [string]$Level = 'INFO'
    )

    $stamp = Get-Date -Format 'HH:mm:ss'
    $line = '[{0}][{1}] {2}' -f $stamp, $Level, $Message

    if ($script:BnqqState.LogFile) {
        Add-Content -LiteralPath $script:BnqqState.LogFile -Value $line -Encoding UTF8
    }

    $color = switch ($Level) {
        'OK'   { 'Green' }
        'WARN' { 'Yellow' }
        'ERR'  { 'Red' }
        'STEP' { 'Cyan' }
        default { 'Gray' }
    }

    Write-Host $line -ForegroundColor $color
}

function Get-RegSnapshot {
    param(
        [string]$Path,
        [string]$Name
    )

    $snapshot = [pscustomobject]@{
        Path    = $Path
        Name    = $Name
        Existed = $false
        Kind    = $null
        Value   = $null
    }

    if (-not (Test-Path -LiteralPath $Path)) { return $snapshot }

    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $key) { return $snapshot }

    try {
        $kind = $key.GetValueKind($Name)
        $snapshot.Existed = $true
        $snapshot.Kind = $kind.ToString()
        $snapshot.Value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    }
    catch {
        $snapshot.Existed = $false
    }

    return $snapshot
}

function Set-BnqqReg {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = 'DWord'
    )

    $key = '{0}|{1}' -f $Path, $Name

    if (-not $script:BnqqState.Backup.ContainsKey($key)) {
        $script:BnqqState.Backup[$key] = Get-RegSnapshot -Path $Path -Name $Name
    }

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }

        if ($null -eq $Value) {
            Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
            return
        }

        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Bnqq ('Registro protegido ou invalido: {0} | {1}' -f $Path, $Name) 'WARN'
    }
}

function Set-BnqqMeta {
    param([string]$Key, $Value)
    $script:BnqqState.Meta[$Key] = $Value
}

function Save-BnqqBackup {
    param([string]$Directory)

    if ($script:BnqqState.Backup.Count -eq 0 -and $script:BnqqState.Meta.Count -eq 0) { return $null }

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    }

    $name = 'backup-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    $file = Join-Path $Directory $name

    $payload = [pscustomobject]@{
        Created = (Get-Date).ToString('o')
        Entries = @($script:BnqqState.Backup.Values)
        Meta    = $script:BnqqState.Meta
    }

    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $file -Encoding UTF8
    return $file
}

function Restore-BnqqBackup {
    param([string]$File)

    $raw = Get-Content -LiteralPath $File -Raw -Encoding UTF8
    $payload = $raw | ConvertFrom-Json
    $count = 0

    foreach ($entry in @($payload.Entries)) {
        if ($null -eq $entry) { continue }

        if ($entry.Existed) {
            if (-not (Test-Path -LiteralPath $entry.Path)) {
                New-Item -Path $entry.Path -Force | Out-Null
            }

            $value = $entry.Value
            if ($entry.Kind -eq 'Binary' -and $null -ne $value) {
                $value = [byte[]]@($value | ForEach-Object { [byte]$_ })
            }

            New-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -Value $value -PropertyType $entry.Kind -Force | Out-Null
        }
        else {
            Remove-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
        }
        $count++
    }

    $meta = $payload.Meta

    if ($meta.PowerPlanId) {
        powercfg /setactive $meta.PowerPlanId 2>$null | Out-Null
        Write-Bnqq ('Plano de energia restaurado: {0}' -f $meta.PowerPlanId) 'OK'
    }

    if ($meta.PagefileAutoManaged -eq $true) {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($cs) {
            Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction SilentlyContinue
            Write-Bnqq 'Gerenciamento automatico de pagefile reativado' 'OK'
        }
    }

    if ($meta.Services) {
        foreach ($svc in $meta.Services.PSObject.Properties) {
            Set-Service -Name $svc.Name -StartupType $svc.Value -ErrorAction SilentlyContinue
            Write-Bnqq ('Servico {0} -> {1}' -f $svc.Name, $svc.Value) 'OK'
        }
    }

    if ($meta.NetAdapter) {
        foreach ($prop in $meta.NetAdapter.PSObject.Properties) {
            try {
                if ($prop.Value.Keyword) {
                    Set-NetAdapterAdvancedProperty -Name $prop.Value.Adapter -RegistryKeyword $prop.Value.Keyword -RegistryValue $prop.Value.Value -ErrorAction Stop
                    Write-Bnqq ('Adaptador {0}: {1} -> {2}' -f $prop.Value.Adapter, $prop.Value.Keyword, $prop.Value.Value) 'OK'
                }
                else {
                    Set-NetAdapterAdvancedProperty -Name $prop.Value.Adapter -DisplayName $prop.Value.Display -DisplayValue $prop.Value.Value -ErrorAction Stop
                    Write-Bnqq ('Adaptador {0}: {1} -> {2}' -f $prop.Value.Adapter, $prop.Value.Display, $prop.Value.Value) 'OK'
                }
            }
            catch {
                Write-Bnqq ('Falha ao restaurar {0}' -f $prop.Value.Display) 'WARN'
            }
        }
    }

    return $count
}

function New-BnqqRestorePoint {
    param([string]$Description = 'BNQQ Optimizer')

    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-Bnqq 'Ponto de restauracao criado' 'OK'
        return $true
    }
    catch {
        Write-Bnqq ('Ponto de restauracao indisponivel: {0}' -f $_.Exception.Message) 'WARN'
        return $false
    }
}

function Test-BnqqCmd {
    param([string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}
