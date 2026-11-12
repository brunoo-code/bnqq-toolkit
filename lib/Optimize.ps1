function Get-BnqqCatalog { return @(Get-BnqqRegistryTargets) }
function Invoke-BnqqApply {
    param([ValidateSet('recording-off','latency')][string]$Profile='recording-off',[switch]$DryRun,[switch]$ForceDeepIdleDisable)
    if($Profile -eq 'latency' -and -not $ForceDeepIdleDisable){
        Show-BnqqDisplayGuidance
        Write-Host 'Nenhuma energia/registro alterado. IDLEDISABLE exige -ForceDeepIdleDisable e HeavyQA.'
        return
    }
    if($Profile -eq 'recording-off'){
        # A documented policy is still not a proof of runtime effect on every build.
        # The local Windows policy definition must advertise this exact target.
        if(-not $DryRun){Assert-BnqqRecordingCapability}
        $t=Get-BnqqRegistryTargets | Select-Object -First 1
        $before=Get-RegSnapshot $t.Path $t.Name
        $after=[pscustomobject]@{Path=$t.Path;Name=$t.Name;KeyExisted=$true;Existed=$true;Kind=$t.Type;Value=$t.Value}
        # KeyExisted refers to the original leaf, and must match the state after writing.
        $op=[pscustomobject]@{Kind='Registry';Before=$before;After=$after}
    } else {
        $before=Get-BnqqPowerSnapshot
        $after=$before | Select-Object *
        $after.AC=1 # DC, boost policy, coalescing and resiliency are never changed.
        $op=[pscustomobject]@{Kind='Power';Before=$before;After=$after}
    }
    if($DryRun){return $op}
    if(-not (Test-BnqqAdmin)){throw 'Aplicacao exige administrador; nenhum auto-elevate silencioso'}
    Assert-BnqqHeavyQa
    $lock=Enter-BnqqStateLock
    try {
        Assert-BnqqNoPendingJournal
        $j=New-BnqqJournal $Profile
        try{Invoke-BnqqJournalOperation $j $op; $j.Data.Status='Applied'; Write-BnqqAtomicJson $j.Data $j.File}
        catch{ $original=$_; try{Restore-BnqqJournal $j.File | Out-Null}catch{Write-Warning $_};throw $original }
        Write-Host ('Aplicado e verificado; restauracao: '+$j.File)
        Write-Host 'Efeito de desempenho ainda nao demonstrado. Compare baseline controlado.'
    }finally{$lock.Dispose()}
}
function Assert-BnqqRecordingCapability {
    $file=Join-Path $env:WINDIR 'PolicyDefinitions\GameDVR.admx'
    if(-not (Test-Path -LiteralPath $file)){throw 'Definicao local GameDVR indisponivel; nao presumir suporte'}
    [xml]$xml=Get-Content -LiteralPath $file -Raw -ErrorAction Stop
    $policy=$xml.SelectSingleNode("//*[local-name()='policy' and @name='AllowGameDVR']")
    if(-not $policy -or $policy.key -ne 'Software\Policies\Microsoft\Windows\GameDVR' -or $policy.valueName -ne 'AllowGameDVR'){throw 'Definicao local diverge do alvo auditado'}
}

function Set-BnqqOptionalServices {
    param([switch]$Restore)

    if (-not (Test-BnqqAdmin)) { throw 'Servicos opcionais exigem administrador.' }
    $lock = Enter-BnqqStateLock
    try {
        foreach ($name in @('Fax', 'MapsBroker')) {
            $file = Join-Path (Get-BnqqDataRoot) "optimizer-service-$name.json"
            $service = Get-Service -Name $name -ErrorAction SilentlyContinue
            if (-not $service) { continue }
            if ($Restore) {
                if (-not (Test-Path -LiteralPath $file)) { continue }
                if ($service.StartType -eq 'Disabled') {
                    Set-Service -Name $name -StartupType Manual -ErrorAction Stop
                }
                if ((Get-Service -Name $name -ErrorAction Stop).StartType -ne 'Manual') {
                    Write-Warning "Servico $name alterado fora do BNQQ. Backup preservado."
                    continue
                }
                Remove-Item -LiteralPath $file -ErrorAction Stop
                Write-Host "$name restaurado para Manual."
                continue
            }
            if ($service.Status -ne 'Stopped' -or $service.StartType -ne 'Manual') {
                Write-Host "$name ignorado (ativo ou com outro tipo de inicializacao)."
                continue
            }
            Write-BnqqAtomicJson -Value @{ Name = $name; StartupType = 'Manual' } -Path $file
            Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
            if ((Get-Service -Name $name -ErrorAction Stop).StartType -ne 'Disabled') {
                throw "Nao foi possivel confirmar a desativacao de $name."
            }
            Write-Host "$name desativado."
        }
    } finally { $lock.Dispose() }
}

function Remove-BnqqOptionalApps {
    $failures = @()
    foreach ($name in @('Microsoft.Copilot', 'Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.MicrosoftSolitaireCollection')) {
        try {
            foreach ($package in @(Get-AppxPackage -Name $name -ErrorAction Stop)) {
                Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
                Write-Host "$name removido da conta atual."
            }
        } catch {
            $failures += $name
            Write-Warning "$name - $($_.Exception.Message)"
        }
    }
    if ($failures.Count) { throw ('Falha ao remover: ' + ($failures -join ', ')) }
}

function Disable-BnqqRecall {
    if (-not (Test-BnqqAdmin)) { throw 'Verificar o Recall exige administrador.' }
    $recall = Get-WindowsOptionalFeature -Online -ErrorAction Stop | Where-Object FeatureName -eq 'Recall'
    if (-not $recall -or $recall.State -in @('Disabled', 'DisabledWithPayloadRemoved')) {
        Write-Host 'Recall ausente ou ja desativado.'
        return
    }
    if ($recall.State -eq 'DisablePending') {
        Write-Host 'Reinicie o Windows para concluir a desativacao do Recall.'
        return
    }
    if ($recall.State -ne 'Enabled') { throw "Recall em estado $($recall.State). Confira apos reiniciar." }
    $result = Disable-WindowsOptionalFeature -Online -FeatureName Recall -NoRestart -ErrorAction Stop
    if ($result.RestartNeeded) {
        Write-Host 'Reinicie o Windows para concluir a desativacao do Recall.'
    } else {
        Write-Host 'Recall desativado.'
    }
}

function Invoke-BnqqQuickOptimizer {
    Write-Host 'Optimizer: energia, navegadores, apps opcionais, Recall, servicos e armazenamento.'
    Write-Host 'Alto desempenho pode aumentar consumo e temperatura.'
    $steps = [ordered]@{
        'Energia' = { Set-BnqqWindowsPowerPlan -Action apply }
        'Navegadores' = {
            $result = Invoke-BnqqAppLite -Action apply
            Write-Host "Apps Lite: $($result.Status). Reabra Edge e Chrome para atualizar as politicas."
        }
        'Apps opcionais' = { Remove-BnqqOptionalApps }
        'Recall' = { Disable-BnqqRecall }
        'Servicos opcionais' = { Set-BnqqOptionalServices }
        'Armazenamento' = {
            if (-not (Test-BnqqAdmin)) { throw 'Manutencao de armazenamento exige administrador.' }
            Write-Host 'Estado das notificacoes TRIM (0 = habilitadas):'
            & fsutil.exe behavior query DisableDeleteNotify
            if ($LASTEXITCODE -ne 0) { Write-Warning 'Nao foi possivel consultar o TRIM.' }
            Optimize-Volume -DriveLetter ($env:SystemDrive.TrimEnd(':')) -Verbose -ErrorAction Stop
        }
    }
    $failures = 0
    foreach ($step in $steps.GetEnumerator()) {
        Write-Host ('--- ' + $step.Key)
        try { & $step.Value } catch {
            Write-Warning ($step.Key + ': ' + $_.Exception.Message)
            $failures++
        }
    }
    Write-Host ('Etapas com pendencias: ' + $failures)
    Write-Host 'Restauracao: menu 31 (energia), 8 (navegadores), 33 (servicos).'
    Write-Host 'Apps opcionais podem ser reinstalados pela Microsoft Store.'
    Write-Host 'Para GPU e perfil por jogo, veja 12, 26 e 27.'
}
