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
    $names = @(
        'Microsoft.Copilot', 'Clipchamp.Clipchamp', 'Microsoft.BingNews',
        'Microsoft.BingWeather', 'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.MicrosoftOfficeHub', 'Microsoft.OutlookForWindows',
        'Microsoft.WindowsSoundRecorder', 'Microsoft.WindowsFeedbackHub',
        'Microsoft.Windows.DevHome', 'Microsoft.Todos', 'Microsoft.PowerAutomateDesktop'
    )
    $lock = Enter-BnqqStateLock
    try {
        $file = Join-Path (Get-BnqqDataRoot) ('optional-apps-' + [guid]::NewGuid().ToString('N') + '.json')
        $report = [ordered]@{
            StartedUtc = [datetime]::UtcNow.ToString('o')
            Status = 'Running'
            Items = @()
        }
        Write-BnqqAtomicJson -Value $report -Path $file
        Write-Host "Relatorio de apps: $file"
        foreach ($name in $names) {
            $entry = [ordered]@{ Name = $name; Status = 'Checking'; Detected = @(); Removed = @(); Error = $null }
            $report.Items += $entry
            try {
                $packages = @(Get-AppxPackage -Name $name -ErrorAction Stop)
                $entry.Detected = @($packages | Select-Object -ExpandProperty PackageFullName)
                if ($packages.Count) {
                    $entry.Status = 'Removing'
                    Write-BnqqAtomicJson -Value $report -Path $file
                    foreach ($package in $packages) {
                        Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
                        if (Get-AppxPackage -Name $name -ErrorAction Stop | Where-Object PackageFullName -eq $package.PackageFullName) {
                            throw "O pacote $($package.PackageFullName) ainda esta registrado."
                        }
                        $entry.Removed += $package.PackageFullName
                        Write-BnqqAtomicJson -Value $report -Path $file
                    }
                    $entry.Status = 'Removed'
                    Write-Host "$name removido da conta atual."
                } else {
                    $entry.Status = 'NotInstalled'
                    Write-Host "$name ausente."
                }
            } catch {
                $entry.Status = 'Failed'
                $entry.Error = $_.Exception.Message
                Write-Warning "$name - $($entry.Error)"
            }
            Write-BnqqAtomicJson -Value $report -Path $file
        }
        $failed = @($report.Items | Where-Object { $_.Status -eq 'Failed' })
        $report.Status = if ($failed.Count) { 'CompletedWithErrors' } else { 'Completed' }
        Write-BnqqAtomicJson -Value $report -Path $file
        if ($failed.Count) { throw ('Falha ao remover: ' + ($failed.Name -join ', ')) }
    } finally { $lock.Dispose() }
}

function Show-BnqqBackgroundReadiness {
    $startup = @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop | Select-Object -ExpandProperty Name -Unique)
    Write-Host "Entradas de inicializacao detectadas: $($startup.Count)"
    foreach ($entry in $startup) { Write-Host "  $entry" }
    $capture = Get-RegSnapshot 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
    if ($capture.Existed) {
        Write-Host "Preferencia de captura GameDVR_Enabled: $($capture.Value). Confira Jogos > Capturas."
    } else {
        Write-Host 'Preferencia de captura ainda nao definida pela conta. Confira Jogos > Capturas.'
    }
}

function Show-BnqqPostInstallReadiness {
    $adapters = @(Get-CimInstance Win32_VideoController -ErrorAction Stop)
    if (-not $adapters.Count) { Write-Host 'Nenhum adaptador grafico detectado.' }
    foreach ($adapter in $adapters) {
        $refresh = if ($adapter.CurrentRefreshRate -gt 1) { "$($adapter.CurrentRefreshRate) Hz" } else { 'indisponivel' }
        Write-Host "$($adapter.Name) | driver $($adapter.DriverVersion) | taxa reportada: $refresh"
    }
    Write-Host 'Confirme a taxa de cada monitor em Tela avancada.'
}

function Show-BnqqPostInstallMenu {
    Show-BnqqBackgroundReadiness
    Show-BnqqPostInstallReadiness
    Write-Host '1 Inicializacao | 2 Capturas | 3 Tela | 4 Energia | 5 Consultar Compact OS | 6 Efeitos visuais | 7 Ajustar inicializacao de apps reconhecidos'
    $choice = Read-Host 'Escolha (Enter para voltar)'
    switch ($choice) {
        '1' { Start-Process 'ms-settings:startupapps' -ErrorAction Stop }
        '2' { Start-Process 'ms-settings:gaming-gamedvr' -ErrorAction Stop }
        '3' { Start-Process 'ms-settings:display' -ErrorAction Stop }
        '4' { Start-Process 'ms-settings:powersleep' -ErrorAction Stop }
        '6' { Start-Process 'ms-settings:easeofaccess-visualeffects' -ErrorAction Stop }
        '7' { Show-BnqqStartupMenu }
        '5' {
            Get-BnqqSystemStorage | Format-List | Out-Host
            & compact.exe /CompactOS:query
            if ($LASTEXITCODE -notin @(0, 102)) { throw "Consulta do Compact OS retornou o codigo $LASTEXITCODE." }
        }
    }
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

function Get-BnqqPointerAcceleration {
    Initialize-BnqqPointerNative
    $state = New-Object 'int[]' 3
    if (-not [Bnqq.PointerNative]::SystemParametersInfo(3, 0, $state, 0)) {
        throw 'Nao foi possivel consultar a aceleracao do ponteiro.'
    }
    return $state[2]
}

function Initialize-BnqqPointerNative {
    if ('Bnqq.PointerNative' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;

namespace Bnqq
{
    public static class PointerNative
    {
        [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW")]
        public static extern bool SystemParametersInfo(uint action, uint parameter, [In, Out] int[] values, uint flags);
    }
}
'@
}

function Set-BnqqPointerAcceleration {
    param([switch]$Restore)

    if (-not [Environment]::UserInteractive) {
        Write-Host 'Ponteiro: ajuste disponivel na sessao interativa do usuario.'
        return
    }
    $lock = Enter-BnqqStateLock
    try {
        $file = Join-Path (Get-BnqqDataRoot) 'optimizer-pointer.json'
        $current = Get-BnqqPointerAcceleration
        $saved = if (Test-Path -LiteralPath $file) {
            Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        if ($Restore -and -not $saved) { Write-Host 'Ponteiro: nenhum backup encontrado.'; return }
        if ($saved -and ($saved.Owner -cne (Get-BnqqOwner) -or $saved.Acceleration -notin @(1, 2))) {
            throw 'Backup de ponteiro invalido.'
        }
        if (-not $Restore -and $current -eq 0) { Write-Host 'Ponteiro: aceleracao ja desligada.'; return }
        if ($saved -and $current -notin @(0, $saved.Acceleration)) {
            throw 'Aceleracao alterada externamente. Backup preservado.'
        }
        if (-not $Restore -and -not $saved) {
            if ($current -notin @(1, 2)) { throw 'Configuracao de aceleracao nao reconhecida.' }
            Write-BnqqAtomicJson -Value @{Owner = Get-BnqqOwner; Acceleration = $current} -Path $file
        }
        $target = if ($Restore) { [int]$saved.Acceleration } else { 0 }
        if ($current -ne $target) {
            $state = New-Object 'int[]' 3
            if (-not [Bnqq.PointerNative]::SystemParametersInfo(3, 0, $state, 0) -or $state[2] -ne $current) {
                throw 'A configuracao do ponteiro mudou durante a operacao.'
            }
            $state[2] = $target
            if (-not [Bnqq.PointerNative]::SystemParametersInfo(4, 0, $state, 3) -or (Get-BnqqPointerAcceleration) -ne $target) {
                throw 'Nao foi possivel confirmar o ajuste do ponteiro.'
            }
        }
        if ($Restore) {
            Remove-Item -LiteralPath $file -ErrorAction Stop
            Write-Host 'Ponteiro: aceleracao original restaurada.'
        } else {
            Write-Host 'Ponteiro: aceleracao do Windows desligada. Velocidade do ponteiro preservada.'
        }
    } finally { $lock.Dispose() }
}

function Set-BnqqWidgetsPolicy {
    param([switch]$Restore)

    if (-not (Test-BnqqAdmin)) { throw 'A politica de Widgets exige administrador.' }
    $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'
    $name = 'AllowNewsAndInterests'
    $lock = Enter-BnqqStateLock
    try {
        $file = Join-Path (Get-BnqqDataRoot) 'optimizer-widgets.json'
        $current = Get-RegSnapshot $path $name
        $saved = if (Test-Path -LiteralPath $file) {
            Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        if ($saved -and ($saved.Owner -cne (Get-BnqqOwner) -or $saved.KeyExisted -isnot [bool])) {
            throw 'Backup de Widgets invalido.'
        }
        if ($Restore) {
            if (-not $saved) { Write-Host 'Widgets: nenhum backup encontrado.'; return }
            if ($current.Existed -and ($current.Kind -ne 'DWord' -or $current.Value -ne 0)) {
                throw 'Politica de Widgets alterada externamente. Backup preservado.'
            }
            Set-BnqqRegistrySnapshot ([pscustomobject]@{Path=$path;Name=$name;KeyExisted=$saved.KeyExisted;Existed=$false})
            if ((Get-RegSnapshot $path $name).Existed) { throw 'Falha ao restaurar a politica de Widgets.' }
            Remove-Item -LiteralPath $file -ErrorAction Stop
            Write-Host 'Politica de Widgets restaurada. Saia e entre novamente para atualizar a barra.'
            return
        }
        if ($current.Existed) { Write-Host 'Widgets: politica existente preservada.'; return }
        $version = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        if ([int]$version.CurrentBuild -lt 22000 -or $version.EditionID -notmatch '^(Professional|Enterprise|Education|IoTEnterprise)') {
            Write-Host 'Widgets: politica ignorada nesta edicao ou versao do Windows.'
            return
        }
        if (-not $saved) {
            Write-BnqqAtomicJson -Value @{Owner = Get-BnqqOwner; KeyExisted = $current.KeyExisted} -Path $file
        }
        try {
            Set-BnqqRegistrySnapshot ([pscustomobject]@{Path=$path;Name=$name;KeyExisted=$true;Existed=$true;Kind='DWord';Value=0})
        } catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
            throw 'Windows negou gravar a politica de Widgets. A permissao da chave foi preservada. Use Configuracoes > Personalizacao > Barra de tarefas se disponivel.'
        }
        $actual = Get-RegSnapshot $path $name
        if (-not $actual.Existed -or $actual.Kind -ne 'DWord' -or $actual.Value -ne 0) {
            throw 'Falha ao confirmar a politica de Widgets.'
        }
        Write-Host 'Widgets desativados. Saia e entre novamente para atualizar a barra.'
    } finally { $lock.Dispose() }
}

function Invoke-BnqqQuickOptimizer {
    param([switch]$ReturnFailureCount)
    Write-Host 'Optimizer pos-formatacao: funciona antes de instalar jogos ou launchers.'
    Write-Host 'BNQQ Competitive pode aumentar consumo e temperatura.'
    $steps = [ordered]@{
        'Energia' = { Set-BnqqWindowsPowerPlan -Action apply }
        'Navegadores' = {
            $result = Invoke-BnqqAppLite -Action apply
            Write-Host "Apps Lite: $($result.Status). Reabra Edge e Chrome para atualizar as politicas."
        }
        'Apps opcionais' = { Remove-BnqqOptionalApps }
        'Inicializacao e captura' = { Show-BnqqBackgroundReadiness }
        'Monitor e driver' = { Show-BnqqPostInstallReadiness }
        'Memoria' = { Get-BnqqMemoryReport | Select-Object AvailableGiB, CommitHeadroomGiB, SeverePressure | Format-List | Out-Host }
        'Recall' = { Disable-BnqqRecall }
        'Ponteiro' = { Set-BnqqPointerAcceleration }
        'Widgets' = { Set-BnqqWidgetsPolicy }
        'Servicos opcionais' = { Set-BnqqOptionalServices }
        'Armazenamento' = {
            if (-not (Test-BnqqAdmin)) { throw 'Manutencao de armazenamento exige administrador.' }
            Write-Host 'Estado das notificacoes TRIM (0 = habilitadas):'
            & fsutil.exe behavior query DisableDeleteNotify
            if ($LASTEXITCODE -ne 0) { Write-Warning 'Nao foi possivel consultar o TRIM.' }
            Optimize-Volume -DriveLetter ($env:SystemDrive.TrimEnd(':')) -Verbose -ErrorAction Stop
        }
    }
    $file = Join-Path (Get-BnqqDataRoot) ('optimizer-run-' + [guid]::NewGuid().ToString('N') + '.json')
    $report = [ordered]@{
        StartedUtc = [datetime]::UtcNow.ToString('o')
        FinishedUtc = $null
        Status = 'Running'
        FailedSteps = 0
        Steps = @()
        RecoveryMenus = @{ Main = 8; Power = 1; Browsers = 2; Services = 3; Pointer = 4; Widgets = 5 }
    }
    foreach ($name in $steps.Keys) {
        $report.Steps += [ordered]@{ Name = $name; Status = 'Pending'; Error = $null }
    }
    Write-BnqqAtomicJson -Value $report -Path $file
    Write-Host "Relatorio da opcao 0: $file"
    foreach ($entry in $report.Steps) {
        Write-Host ('--- ' + $entry.Name)
        $entry.Status = 'Running'
        Write-BnqqAtomicJson -Value $report -Path $file
        try {
            & $steps[$entry.Name] | Out-Host
            $entry.Status = 'Completed'
        } catch {
            $entry.Status = 'Failed'
            $entry.Error = $_.Exception.Message
            $report.FailedSteps++
            Write-Warning ($entry.Name + ': ' + $entry.Error)
        }
        Write-BnqqAtomicJson -Value $report -Path $file
    }
    $report.FinishedUtc = [datetime]::UtcNow.ToString('o')
    $report.Status = if ($report.FailedSteps) { 'CompletedWithErrors' } else { 'Completed' }
    Write-BnqqAtomicJson -Value $report -Path $file
    $failures = $report.FailedSteps
    Write-Host ('Etapas com pendencias: ' + $failures)
    Write-Host 'Para desfazer um ajuste, abra 8 - Restaurar configuracoes.'
    Write-Host 'Apps opcionais podem ser reinstalados pela Microsoft Store.'
    if ($ReturnFailureCount) { return $failures }
    Write-Host 'Ferramentas por jogo: menu 9.'
}
