function Get-BnqqGodCfgStatus {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($game in @('cs2.exe', 'VALORANT-Win64-Shipping.exe')) {
        $state = 'padrao'
        try {
            $mitigation = Get-ProcessMitigation -Name $game -ErrorAction Stop
            if ($mitigation -and $mitigation.Cfg) {
                if ($mitigation.Cfg.Enable -eq 'OFF') { $state = 'desativado' }
                elseif ($mitigation.Cfg.Enable -eq 'ON') { $state = 'habilitado' }
            }
        }
        catch { $state = 'indisponivel' }
        $rows.Add([pscustomobject]@{ Game = $game; State = $state; Ok = ($state -eq 'desativado') })
    }
    return $rows.ToArray()
}

function Set-BnqqGodCfgPerGame {
    if (-not (Get-Command Set-ProcessMitigation -ErrorAction SilentlyContinue)) {
        Write-Bnqq 'CFG: Set-ProcessMitigation indisponivel; nada alterado' 'WARN'
        return
    }

    foreach ($game in @('cs2.exe', 'VALORANT-Win64-Shipping.exe')) {
        try {
            Set-ProcessMitigation -Name $game -Disable CFG -ErrorAction Stop
            Write-Bnqq ('CFG desativado apenas para {0}' -f $game) 'OK'
        }
        catch {
            Write-Bnqq ('CFG {0}: {1}' -f $game, $_.Exception.Message) 'WARN'
        }
    }
}

function Reset-BnqqGodCfgPerGame {
    if (-not (Get-Command Set-ProcessMitigation -ErrorAction SilentlyContinue)) { return }

    foreach ($game in @('cs2.exe', 'VALORANT-Win64-Shipping.exe')) {
        try {
            Set-ProcessMitigation -Name $game -Enable CFG -ErrorAction Stop
            Write-Bnqq ('CFG reabilitado para {0}' -f $game) 'OK'
        }
        catch {
            Write-Bnqq ('CFG reset {0}: {1}' -f $game, $_.Exception.Message) 'WARN'
        }
    }
}

function Get-BnqqGodFsoStatus {
    $layers = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    $rows = New-Object System.Collections.Generic.List[object]
    $exes = @(Get-BnqqGameExes)
    foreach ($game in @('cs2.exe', 'VALORANT-Win64-Shipping.exe')) {
        $path = $exes | Where-Object { [IO.Path]::GetFileName($_) -ieq $game } | Select-Object -First 1
        if (-not $path) {
            $rows.Add([pscustomobject]@{ Game = $game; Path = $null; Value = $null; Ok = $false })
            continue
        }

        $props = Get-ItemProperty -LiteralPath $layers -Name $path -ErrorAction SilentlyContinue
        $value = if ($props) { $props.$path } else { $null }
        $rows.Add([pscustomobject]@{
            Game  = $game
            Path  = $path
            Value = $value
            Ok    = [bool]($value -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE')
        })
    }
    return $rows.ToArray()
}

function Get-BnqqShaderCacheStatus {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache'),
        (Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache'),
        (Join-Path $env:LOCALAPPDATA 'D3DSCache')
    )

    $rows = @()
    $total = 0
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $size = (Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        if ($size) { $total += $size }
        $rows += [pscustomobject]@{ Path = $path; MB = [math]::Round($size / 1MB, 1) }
    }

    return [pscustomobject]@{
        Paths         = $rows
        TotalMB       = [math]::Round($total / 1MB, 1)
        DriverControl = 'NVIDIA App / driver profile (sem chave de registro suportada)'
        Applied       = $false
    }
}

function Get-BnqqGodTierStatus {
    $mm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    $priority = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'
    $paging = (Get-ItemProperty -LiteralPath $mm -Name DisablePagingExecutive -ErrorAction SilentlyContinue).DisablePagingExecutive
    $separation = (Get-ItemProperty -LiteralPath $priority -Name Win32PrioritySeparation -ErrorAction SilentlyContinue).Win32PrioritySeparation
    $cfg = @(Get-BnqqGodCfgStatus)
    $fso = @(Get-BnqqGodFsoStatus)
    $shader = Get-BnqqShaderCacheStatus

    $cfgOk = @($cfg | Where-Object { $_.Ok }).Count -eq 2
    $fsoOk = @($fso | Where-Object { $_.Ok }).Count -eq 2
    $allOk = ($paging -eq 1) -and ($separation -eq 38) -and $cfgOk -and $fsoOk

    return [pscustomobject]@{
        DisablePagingExecutive = $paging
        Win32PrioritySeparation = $separation
        Cfg = $cfg
        CfgOk = $cfgOk
        Fso = $fso
        FsoOk = $fsoOk
        Shader = $shader
        AllOk = $allOk
    }
}

function Set-BnqqGodTier {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para aplicar o God-Tier' }

    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive' 1 'DWord'
    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38 'DWord'
    Set-BnqqGodCfgPerGame
    Set-BnqqFullscreenOptimizations
    Set-BnqqMeta 'GodTierApplied' $true

    Write-Bnqq 'God-Tier: paging executive, prioridade 0x26, CFG por jogo e FSO (reboot)' 'OK'
}

function Reset-BnqqGodTier {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para remover o God-Tier' }

    Set-BnqqReg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 26 'DWord'
    Reset-BnqqGodCfgPerGame
    Set-BnqqMeta 'GodTierApplied' $false

    Write-Bnqq 'God-Tier removido: prioridade 26 decimal e CFG reabilitado (reboot)' 'OK'
}

function Show-BnqqGodTierStatus {
    param($Status)

    if (-not $Status) { $Status = Get-BnqqGodTierStatus }

    Write-Host ''
    Write-Host '  GOD-TIER / KERNEL' -ForegroundColor Cyan
    $pagingColor = if ($Status.DisablePagingExecutive -eq 1) { 'Green' } else { 'Yellow' }
    $prioColor = if ($Status.Win32PrioritySeparation -eq 38) { 'Green' } else { 'Yellow' }
    Write-Host ('    DisablePagingExecutive  {0}  [{1}]' -f $Status.DisablePagingExecutive, $(if ($Status.DisablePagingExecutive -eq 1) { 'OK' } else { 'PENDENTE' })) -ForegroundColor $pagingColor
    Write-Host ('    PrioritySeparation      0x{0:X} ({0})  [{1}]' -f $Status.Win32PrioritySeparation, $(if ($Status.Win32PrioritySeparation -eq 38) { 'OK' } else { 'PENDENTE' })) -ForegroundColor $prioColor

    foreach ($row in @($Status.Cfg)) {
        $color = if ($row.Ok) { 'Green' } else { 'Yellow' }
        Write-Host ('    CFG {0,-27} {1}' -f $row.Game, $row.State) -ForegroundColor $color
    }
    foreach ($row in @($Status.Fso)) {
        $color = if ($row.Ok) { 'Green' } else { 'Yellow' }
        $value = if ($row.Value) { $row.Value } else { 'nao encontrado' }
        Write-Host ('    FSO {0,-27} {1}' -f $row.Game, $value) -ForegroundColor $color
    }

    Write-Host ('    Shader cache            {0} MB em {1} pasta(s)' -f $Status.Shader.TotalMB, @($Status.Shader.Paths).Count) -ForegroundColor Gray
    Write-Host ('    Driver shader control   {0}' -f $Status.Shader.DriverControl) -ForegroundColor DarkGray
    Write-Host '    Nota                    CFG por jogo e anti-cheat: opt-in; nao altera o sistema inteiro' -ForegroundColor DarkGray
    Write-Host ''
}
