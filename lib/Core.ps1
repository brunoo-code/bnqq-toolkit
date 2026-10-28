$ErrorActionPreference = 'Continue'

$script:State = @{
    Log    = $null
    Backup = @{}
    Meta   = @{}
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Elevation {
    param([string]$Script, [string[]]$ScriptArgs = @())

    if (Test-Admin) { return }

    $shell = (Get-Process -Id $PID).Path
    $list = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Script`"") + $ScriptArgs
    Start-Process -FilePath $shell -ArgumentList $list -Verb RunAs
    exit 0
}

function Start-Log {
    param([string]$Dir)

    if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
    $file = Join-Path $Dir ('bnqq-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Set-Content -LiteralPath $file -Value '' -Encoding UTF8
    $script:State.Log = $file
    return $file
}

function Write-Step {
    param([string]$Message)
    Write-Log -Message $Message -Level 'STEP'
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERR', 'STEP')]
        [string]$Level = 'INFO'
    )

    $line = '[{0}][{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message

    if ($script:State.Log) { Add-Content -LiteralPath $script:State.Log -Value $line -Encoding UTF8 }

    $color = switch ($Level) {
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'ERR' { 'Red' }
        'STEP' { 'Cyan' }
        default { 'Gray' }
    }
    Write-Host $line -ForegroundColor $color
}

function Get-RegSnapshot {
    param([string]$Path, [string]$Name)

    $snap = [pscustomobject]@{ Path = $Path; Name = $Name; Existed = $false; Kind = $null; Value = $null }

    if (-not (Test-Path -LiteralPath $Path)) { return $snap }

    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $key) { return $snap }

    try {
        $snap.Kind = $key.GetValueKind($Name).ToString()
        $snap.Value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $snap.Existed = $true
    }
    catch { $snap.Existed = $false }

    return $snap
}

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')

    $id = '{0}|{1}' -f $Path, $Name
    if (-not $script:State.Backup.ContainsKey($id)) {
        $script:State.Backup[$id] = Get-RegSnapshot -Path $Path -Name $Name
    }

    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }

    if ($null -eq $Value) {
        Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
        return
    }

    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Set-Meta {
    param([string]$Key, $Value)
    $script:State.Meta[$Key] = $Value
}

function Save-Backup {
    param([string]$Dir)

    if ($script:State.Backup.Count -eq 0 -and $script:State.Meta.Count -eq 0) { return $null }
    if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Force -Path $Dir | Out-Null }

    $file = Join-Path $Dir ('backup-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    [pscustomobject]@{
        Created = (Get-Date).ToString('o')
        Entries = @($script:State.Backup.Values)
        Meta    = $script:State.Meta
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $file -Encoding UTF8

    return $file
}

function Restore-Backup {
    param([string]$File)

    $data = Get-Content -LiteralPath $File -Raw -Encoding UTF8 | ConvertFrom-Json
    $count = 0

    foreach ($e in @($data.Entries)) {
        if ($null -eq $e) { continue }

        if ($e.Existed) {
            if (-not (Test-Path -LiteralPath $e.Path)) { New-Item -Path $e.Path -Force | Out-Null }
            New-ItemProperty -LiteralPath $e.Path -Name $e.Name -Value $e.Value -PropertyType $e.Kind -Force | Out-Null
        }
        else {
            Remove-ItemProperty -LiteralPath $e.Path -Name $e.Name -ErrorAction SilentlyContinue
        }
        $count++
    }

    $meta = $data.Meta

    if ($meta.PowerPlanId) {
        powercfg /setactive $meta.PowerPlanId 2>$null | Out-Null
        Write-Log 'Plano de energia anterior reativado' 'OK'
    }

    if ($meta.Services) {
        foreach ($s in $meta.Services.PSObject.Properties) {
            Set-Service -Name $s.Name -StartupType $s.Value -ErrorAction SilentlyContinue
        }
        Write-Log 'Servicos restaurados' 'OK'
    }

    if ($meta.NetAdapter) {
        foreach ($p in $meta.NetAdapter.PSObject.Properties) {
            try {
                Set-NetAdapterAdvancedProperty -Name $p.Value.Adapter -DisplayName $p.Value.Display -DisplayValue $p.Value.Value -ErrorAction Stop
            }
            catch { }
        }
        Write-Log 'Adaptador de rede restaurado' 'OK'
    }

    return $count
}

function New-RestorePoint {
    param([string]$Description = 'BNQQ Toolkit')

    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-Log 'Ponto de restauracao criado' 'OK'
        return $true
    }
    catch {
        Write-Log ('Ponto de restauracao indisponivel: {0}' -f $_.Exception.Message) 'WARN'
        return $false
    }
}

function Test-Cmd {
    param([string]$Name)
    [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}
