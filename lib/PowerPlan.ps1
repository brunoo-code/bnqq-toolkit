function Get-BnqqActivePowerPlanId {
    $result = & powercfg.exe /getactivescheme
    $match = [regex]::Match(($result -join ' '), '\b[0-9a-fA-F-]{36}\b')
    if ($LASTEXITCODE -ne 0 -or -not $match.Success) {
        throw 'Nao foi possivel identificar o plano ativo.'
    }
    return [guid]$match.Value
}

function Show-BnqqPowerPlanMenu {
    Write-Host 'Plano ativo e planos disponiveis'
    & powercfg.exe /list
    $choice = Read-Host '1 = aplicar BNQQ Competitive | 2 = restaurar plano anterior | 0 = voltar'
    if ($choice -notin @('1','2')) { return }
    Set-BnqqWindowsPowerPlan -Action $(if ($choice -eq '1') { 'apply' } else { 'restore' })
}

function Invoke-BnqqPowerCfg {
    param([string[]]$Arguments)
    $result = & powercfg.exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw ('powercfg falhou: ' + ($Arguments -join ' ') + '. ' + ($result -join ' ')) }
    $result
}

function Set-BnqqWindowsPowerPlan {
    param([ValidateSet('apply','restore')][string]$Action)
    $legacy = [guid]'8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    $competitive = [guid]'29088e2a-ce96-46e7-bcd6-c6d967809da3'
    if ($Action -eq 'apply') {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        if ([System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq 'Offline') {
            Write-Host 'BNQQ Competitive ignorado: PC funcionando na bateria.'
            return
        }
    }

    $lock = Enter-BnqqStateLock
    try {
        $file = Join-Path (Get-BnqqDataRoot) 'previous-power-plan.json'
        $active = Get-BnqqActivePowerPlanId
        $saved = if (Test-Path -LiteralPath $file) {
            Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        $previous = if ($saved) { [guid]$saved.Previous }
        $lastApplied = if ($saved -and $saved.Applied) { [guid]$saved.Applied } else { $legacy }
        if ($saved -and $lastApplied -notin @($legacy, $competitive)) {
            throw 'Plano aplicado no backup nao reconhecido.'
        }
        $recoveringLegacy = $saved -and $lastApplied -eq $competitive -and $saved.TransitionFrom -eq $legacy.ToString()
        if ($saved -and $active -notin @($previous, $lastApplied) -and -not ($recoveringLegacy -and $active -eq $legacy)) {
            throw 'O plano ativo foi alterado fora do BNQQ. Confira em Opcoes de Energia.'
        }

        if ($Action -eq 'apply') {
            if ($active -eq $competitive) { Write-Host 'BNQQ Competitive ja esta ativo.'; return }
            $plans = Invoke-BnqqPowerCfg @('/list')
            $imported = ($plans -join ' ') -notmatch [regex]::Escape($competitive.ToString())
            if ($imported) {
                $asset = Join-Path $script:BnqqRoot 'config\BNQQ Competitive Original.pow'
                if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) { throw 'Arquivo do plano BNQQ ausente.' }
                Invoke-BnqqPowerCfg @('/import', $asset, $competitive.ToString()) | Out-Host
            }
            try {
                # Keep the exported plan as the source and normalize its most aggressive settings.
                foreach ($mode in '/setacvalueindex','/setdcvalueindex') {
                    foreach ($setting in @(@('IDLEDISABLE','0'), @('IDLEDEMOTE','40'), @('IDLEPROMOTE','60'), @('PROCTHROTTLEMIN','5'))) {
                        Invoke-BnqqPowerCfg @($mode, $competitive.ToString(), 'SUB_PROCESSOR', $setting[0], $setting[1]) | Out-Host
                    }
                }
                Invoke-BnqqPowerCfg @('/setdcvalueindex', $competitive.ToString(), 'SUB_DISK', 'DISKIDLE', '1200') | Out-Host
                Invoke-BnqqPowerCfg @('/setdcvalueindex', $competitive.ToString(), '2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226', '1') | Out-Host
                Invoke-BnqqPowerCfg @('/setdcvalueindex', $competitive.ToString(), '2a737441-1930-4402-8d77-b2bebba308a3', 'd4e98f31-5ffe-4ce1-be31-1b38b384c009', '2') | Out-Host
                Invoke-BnqqPowerCfg @('/changename', $competitive.ToString(), 'BNQQ Competitive - BnqqOS', 'Perfil competitivo BNQQ com repouso da CPU preservado') | Out-Host
            } catch {
                $failure = $_
                if ($imported) { try { Invoke-BnqqPowerCfg @('/delete', $competitive.ToString()) | Out-Host } catch { Write-Warning $_ } }
                throw $failure
            }
            if (-not $saved) { $previous = $active }
            $target = $competitive
            Write-BnqqAtomicJson -Value @{ Previous = $previous.ToString(); Applied = $target.ToString(); TransitionFrom = $active.ToString() } -Path $file
        } else {
            if (-not $saved) { Write-Host 'Nenhum plano anterior salvo pelo BNQQ.'; return }
            $target = $previous
        }
        if ($active -ne $target) {
            Invoke-BnqqPowerCfg @('/setactive', $target.ToString()) | Out-Host
            if ((Get-BnqqActivePowerPlanId) -ne $target) { throw 'Nao foi possivel confirmar a troca do plano.' }
        }
        if ($Action -eq 'restore') { Remove-Item -LiteralPath $file -ErrorAction Stop }
        Invoke-BnqqPowerCfg @('/getactivescheme') | Out-Host
        Write-Host 'Plano confirmado. Nao precisa reiniciar.'
    } finally { $lock.Dispose() }
}
