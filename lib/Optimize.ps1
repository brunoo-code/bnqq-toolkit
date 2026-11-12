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
    $failures = @()
    try {
        foreach ($name in @('SysMain', 'TapiSrv', 'PhoneSvc', 'Fax', 'MapsBroker', 'ehSched')) {
            try {
                $file = Join-Path (Get-BnqqDataRoot) "optimizer-service-$name.json"
                $service = Get-Service -Name $name -ErrorAction SilentlyContinue
                if (-not $service) { continue }
                $saved = if (Test-Path -LiteralPath $file) {
                    Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                }
                if ($Restore) {
                    if (-not $saved) { continue }
                    if ($service.StartType -eq 'Disabled') {
                        if ($saved.Delayed) {
                            & sc.exe config $name 'start=' 'delayed-auto' | Out-Host
                            if ($LASTEXITCODE -ne 0) { throw 'Falha ao restaurar inicio automatico atrasado.' }
                        } else {
                            Set-Service -Name $name -StartupType $saved.StartupType -ErrorAction Stop
                        }
                    }
                    if ((Get-Service -Name $name -ErrorAction Stop).StartType -ne $saved.StartupType) {
                        throw 'Tipo de inicio divergente. Backup preservado.'
                    }
                    if ($saved.WasRunning -and (Get-Service -Name $name -ErrorAction Stop).Status -ne 'Running') {
                        Start-Service -Name $name -ErrorAction Stop
                    }
                    Remove-Item -LiteralPath $file -ErrorAction Stop
                    Write-Host "$name restaurado."
                    continue
                }
                if ($service.StartType -eq 'Disabled') { continue }
                if ($name -ne 'SysMain' -and ($service.Status -ne 'Stopped' -or $service.StartType -ne 'Manual')) {
                    Write-Host "$name ignorado (ativo ou com outro tipo de inicializacao)."
                    continue
                }
                if ($service.Status -notin @('Running', 'Stopped') -or $service.StartType -notin @('Manual', 'Automatic')) {
                    throw 'Servico em transicao ou com tipo de inicio inesperado.'
                }
                if (-not $saved) {
                    $reg = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$name" -ErrorAction Stop
                    Write-BnqqAtomicJson -Value @{
                        Name = $name
                        StartupType = $service.StartType.ToString()
                        Delayed = $service.StartType -eq 'Automatic' -and $reg.PSObject.Properties['DelayedAutoStart'].Value -eq 1
                        WasRunning = $service.Status -eq 'Running'
                    } -Path $file
                }
                if ($service.Status -eq 'Running') { Stop-Service -Name $name -ErrorAction Stop }
                Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
                $actual = Get-Service -Name $name -ErrorAction Stop
                if ($actual.StartType -ne 'Disabled' -or $actual.Status -ne 'Stopped') {
                    throw 'Nao foi possivel confirmar a desativacao.'
                }
                Write-Host "$name desativado."
            } catch {
                $failures += $name
                Write-Warning "$name - $($_.Exception.Message)"
            }
        }
    } finally { $lock.Dispose() }
    if ($failures.Count) { throw ('Servicos com pendencias: ' + ($failures -join ', ')) }
}

function Remove-BnqqOptionalApps {
    $failures = @()
    foreach ($name in @('Microsoft.Copilot', 'Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.OutlookForWindows')) {
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
    param([switch]$ReturnFailureCount)
    Write-Host 'Optimizer pos-formatacao: funciona antes de instalar jogos ou launchers.'
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
        try { & $step.Value | Out-Host } catch {
            Write-Warning ($step.Key + ': ' + $_.Exception.Message)
            $failures++
        }
    }
    Write-Host ('Etapas com pendencias: ' + $failures)
    Write-Host 'Restauracao: menu 31 (energia), 8 (navegadores), 33 (servicos).'
    Write-Host 'Apps opcionais podem ser reinstalados pela Microsoft Store.'
    if ($ReturnFailureCount) { return $failures }
    Write-Host 'Para GPU e perfil por jogo, veja 12, 26 e 27.'
}
