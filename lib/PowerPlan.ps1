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
    Write-Host 'Alto desempenho pode aumentar consumo e temperatura.'
    $choice = Read-Host '1 = aplicar Alto desempenho | 2 = restaurar plano anterior | 0 = voltar'
    if ($choice -notin @('1','2')) { return }
    Set-BnqqWindowsPowerPlan -Action $(if ($choice -eq '1') { 'apply' } else { 'restore' })
}

function Set-BnqqWindowsPowerPlan {
    param([ValidateSet('apply','restore')][string]$Action)
    $performance = [guid]'8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    $lock = Enter-BnqqStateLock
    try {
        $file = Join-Path (Get-BnqqDataRoot) 'previous-power-plan.json'
        $active = Get-BnqqActivePowerPlanId
        $saved = if (Test-Path -LiteralPath $file) {
            [guid](Get-Content -LiteralPath $file -Raw | ConvertFrom-Json).Previous
        }
        if ($Action -eq 'apply') {
            if ($active -eq $performance) { Write-Host 'Alto desempenho ja esta ativo.'; return }
            if ($saved -and $saved -ne $active) { throw 'Restaure a sessao anterior antes de aplicar outra.' }
            $plans = & powercfg.exe /list
            if ($LASTEXITCODE -ne 0 -or ($plans -join ' ') -notmatch [regex]::Escape($performance.ToString())) {
                throw 'Alto desempenho nao esta disponivel neste PC.'
            }
            if (-not $saved) {
                Write-BnqqAtomicJson -Value @{ Previous = $active.ToString() } -Path $file
            }
            $target = $performance
        } else {
            if (-not $saved) { Write-Host 'Nenhum plano anterior salvo pelo BNQQ.'; return }
            if ($active -ne $performance -and $active -ne $saved) {
                throw 'O plano ativo foi alterado fora do BNQQ. Confira em Opcoes de Energia.'
            }
            $target = $saved
        }
        if ($active -ne $target) {
            & powercfg.exe /setactive $target.ToString()
            if ($LASTEXITCODE -ne 0 -or (Get-BnqqActivePowerPlanId) -ne $target) {
                throw 'Nao foi possivel confirmar a troca do plano.'
            }
        }
        if ($Action -eq 'restore') { Remove-Item -LiteralPath $file -ErrorAction Stop }
        & powercfg.exe /getactivescheme
        Write-Host 'Plano confirmado. Nao precisa reiniciar.'
    } finally { $lock.Dispose() }
}
