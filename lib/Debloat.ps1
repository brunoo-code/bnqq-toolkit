$script:BloatApps = @(
    'Microsoft.BingNews'
    'Microsoft.BingWeather'
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'
    'Microsoft.MicrosoftOfficeHub'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.Microsoft3DViewer'
    'Microsoft.MixedReality.Portal'
    'Microsoft.People'
    'Microsoft.SkypeApp'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.WindowsMaps'
    'Microsoft.YourPhone'
    'Microsoft.OneConnect'
    'Microsoft.Print3D'
    'Microsoft.Todos'
    'Microsoft.PowerAutomateDesktop'
    'Microsoft.WindowsCommunicationsApps'
    'MicrosoftTeams'
    'Clipchamp.Clipchamp'
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxApp'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.549981C3F5F10'
)

$script:BloatTasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
    '\Microsoft\Windows\Application Experience\StartupAppTask'
    '\Microsoft\Windows\Application Experience\PcaPatchDbTask'
    '\Microsoft\Windows\Autochk\Proxy'
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
    '\Microsoft\Windows\Feedback\Siuf\DmClient'
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
    '\Microsoft\Windows\Maintenance\WinSAT'
    '\Microsoft\Windows\PI\Sqm-Tasks'
    '\Microsoft\Windows\NetTrace\GatherNetworkInfo'
    '\Microsoft\Windows\CloudExperienceHost\CreateObjectTask'
    '\Microsoft\Windows\ApplicationData\DsSvcCleanup'
    '\Microsoft\Windows\Diagnosis\Scheduled'
    '\Microsoft\Windows\Device Information\Device'
)

$script:BloatFeatures = @(
    'SMB1Protocol'
    'WorkFolders-Client'
    'Printing-XPSServices-Features'
    'MicrosoftWindowsPowerShellV2'
    'MicrosoftWindowsPowerShellV2Root'
    'Simple-TCPIP'
    'TFTP-Client'
    'TelnetClient'
    'RemoteAssistance'
)

function Get-BnqqAppxAudit {
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($name in $script:BloatApps) {
        $pkg = Get-AppxPackage -Name $name -ErrorAction SilentlyContinue
        if (-not $pkg) { continue }
        $rows.Add([pscustomobject]@{
            Name    = $name
            Version = $pkg.Version
            SizeMB  = if ($pkg.InstallLocation -and (Test-Path $pkg.InstallLocation)) {
                [math]::Round((Get-ChildItem $pkg.InstallLocation -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object Length -Sum).Sum / 1MB, 1)
            } else { 0 }
        })
    }

    return $rows
}

function Get-BnqqTaskAudit {
    $rows = New-Object System.Collections.Generic.List[object]
    $all = @(Get-ScheduledTask -ErrorAction SilentlyContinue)

    foreach ($task in $all) {
        $full = '{0}{1}' -f $task.TaskPath, $task.TaskName
        $matched = $false
        foreach ($prefix in $script:BloatTasks) {
            if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $matched = $true; break }
        }
        if (-not $matched) { continue }

        $rows.Add([pscustomobject]@{
            Path  = $full
            State = $task.State.ToString()
        })
    }

    return $rows
}

function Get-BnqqFeatureAudit {
    if (-not (Test-BnqqAdmin)) { return @() }

    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($name in $script:BloatFeatures) {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction SilentlyContinue
        if (-not $f) { continue }
        $rows.Add([pscustomobject]@{
            Name  = $name
            State = $f.State.ToString()
        })
    }

    return $rows
}

function Show-BnqqDebloat {
    $apps = Get-BnqqAppxAudit
    $tasks = Get-BnqqTaskAudit
    $features = Get-BnqqFeatureAudit

    Write-Host ''
    Write-Host '  DEBLOAT' -ForegroundColor Cyan
    Write-Host ''

    Write-Host '  APPS PRE-INSTALADOS' -ForegroundColor White
    if ($apps.Count -eq 0) {
        Write-Host '    Nenhum app de bloat instalado' -ForegroundColor Green
    }
    else {
        $total = ($apps | Measure-Object SizeMB -Sum).Sum
        foreach ($a in $apps) {
            Write-Host ('    {0,-42} {1,7} MB' -f $a.Name, $a.SizeMB) -ForegroundColor Yellow
        }
        Write-Host ('    Total: {0} apps, {1} MB' -f $apps.Count, [math]::Round($total, 1)) -ForegroundColor Cyan
    }
    Write-Host ''

    Write-Host '  TAREFAS AGENDADAS' -ForegroundColor White
    $enabled = @($tasks | Where-Object { $_.State -ne 'Disabled' })
    if ($enabled.Count -eq 0) {
        Write-Host '    Nenhuma tarefa de telemetria ativa' -ForegroundColor Green
    }
    else {
        foreach ($t in $enabled) {
            Write-Host ('    [{0}] {1}' -f $t.State, (Split-Path $t.Path -Leaf)) -ForegroundColor Yellow
        }
    }
    Write-Host ''

    Write-Host '  RECURSOS DO WINDOWS' -ForegroundColor White
    foreach ($f in $features) {
        $color = if ($f.State -eq 'Enabled') { 'Yellow' } else { 'Green' }
        Write-Host ('    {0,-38} {1}' -f $f.Name, $f.State) -ForegroundColor $color
    }
    Write-Host ''

    $mgmt = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    $paging = (Get-ItemProperty $mgmt -Name DisablePagingExecutive -ErrorAction SilentlyContinue).DisablePagingExecutive
    $lastAccess = (fsutil behavior query disablelastaccess 2>$null) -join ' '
    $netbios = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' -ErrorAction SilentlyContinue |
        Where-Object { $_.TcpipNetbiosOptions -ne 2 })

    Write-Host '  AJUSTES DE KERNEL' -ForegroundColor White
    Write-Host ('    DisablePagingExecutive   {0}' -f $(if ($paging -eq 1) { 'ativo' } else { 'padrao' })) -ForegroundColor $(if ($paging -eq 1) { 'Green' } else { 'Yellow' })
    Write-Host ('    disablelastaccess        {0}' -f $(if ($lastAccess -match '1') { 'desativado' } else { 'padrao' })) -ForegroundColor $(if ($lastAccess -match '1') { 'Green' } else { 'Yellow' })
    Write-Host ('    NetBIOS em adaptadores    {0}' -f $(if ($netbios.Count -eq 0) { 'desativado' } else { $netbios.Count.ToString() + ' com NetBIOS' })) -ForegroundColor $(if ($netbios.Count -eq 0) { 'Green' } else { 'Yellow' })
    Write-Host ''
}

function Set-BnqqDebloatAppx {
    $removed = New-Object System.Collections.Generic.List[string]
    $failed = 0

    foreach ($name in $script:BloatApps) {
        $pkg = Get-AppxPackage -AllUsers -Name $name -ErrorAction SilentlyContinue
        if (-not $pkg) { continue }

        try {
            $pkg | Remove-AppxPackage -AllUsers -ErrorAction Stop
            $removed.Add($name)
            Write-Bnqq ('Removido: {0}' -f $name) 'OK'
        }
        catch {
            $failed++
            Write-Bnqq ('Falha ao remover {0}: {1}' -f $name, $_.Exception.Message) 'WARN'
        }

        $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq $name }
        if ($prov) {
            try {
                $prov | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null
            }
            catch { }
        }
    }

    if ($removed.Count -gt 0) { Set-BnqqMeta 'RemovedAppx' @($removed) }
    Write-Bnqq ('{0} app(s) removido(s), {1} falha(s)' -f $removed.Count, $failed) 'STEP'
}

function Set-BnqqScheduledTasks {
    $disabled = 0
    $all = @(Get-ScheduledTask -ErrorAction SilentlyContinue)

    foreach ($task in $all) {
        $full = '{0}{1}' -f $task.TaskPath, $task.TaskName
        $matched = $false
        foreach ($prefix in $script:BloatTasks) {
            if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $matched = $true; break }
        }
        if (-not $matched) { continue }
        if ($task.State -eq 'Disabled') { continue }

        try {
            Disable-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction Stop | Out-Null
            $disabled++
            Write-Bnqq ('Tarefa desativada: {0}' -f $task.TaskName) 'OK'
        }
        catch {
            Write-Bnqq ('Falha na tarefa: {0}' -f $task.TaskName) 'WARN'
        }
    }

    foreach ($nv in @($all | Where-Object { $_.TaskName -like 'NvTm*' -and $_.State -ne 'Disabled' })) {
        try {
            Disable-ScheduledTask -TaskPath $nv.TaskPath -TaskName $nv.TaskName -ErrorAction Stop | Out-Null
            $disabled++
            Write-Bnqq ('Tarefa NVIDIA desativada: {0}' -f $nv.TaskName) 'OK'
        }
        catch { }
    }

    Write-Bnqq ('{0} tarefa(s) desativada(s)' -f $disabled) 'STEP'
}

function Set-BnqqOptionalFeatures {
    $disabled = 0

    foreach ($name in $script:BloatFeatures) {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction SilentlyContinue
        if (-not $f -or $f.State -ne 'Enabled') { continue }

        try {
            Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart -ErrorAction Stop | Out-Null
            $disabled++
            Write-Bnqq ('Recurso desativado: {0}' -f $name) 'OK'
        }
        catch {
            Write-Bnqq ('Falha no recurso: {0}' -f $name) 'WARN'
        }
    }

    Write-Bnqq ('{0} recurso(s) desativado(s)' -f $disabled) 'STEP'
}

function Set-BnqqFilesystem {
    & fsutil behavior set disablelastaccess 1 2>$null | Out-Null
    & fsutil behavior set memoryusage 2 2>$null | Out-Null
    Write-Bnqq 'NTFS: last access desativado, memory usage em 2' 'OK'
}

function Set-BnqqKernelMemory {
    $mm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    Set-BnqqReg $mm 'DisablePagingExecutive' 1
    Set-BnqqReg $mm 'LargeSystemCache' 0
    Set-BnqqReg $mm 'ClearPageFileAtShutdown' 0

    $crash = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
    Set-BnqqReg $crash 'CrashDumpEnabled' 1
    Set-BnqqReg $crash 'AutoReboot' 0

    Write-Bnqq 'Kernel mantido em RAM, dump reduzido' 'OK'
}

function Set-BnqqDeliveryOptimization {
    Set-BnqqReg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' 'DODownloadMode' 0
    Set-BnqqReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
    Write-Bnqq 'Delivery Optimization: P2P desativado' 'OK'
}

function Set-BnqqNetbiosOff {
    $nics = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' -ErrorAction SilentlyContinue)
    $changed = 0

    foreach ($nic in $nics) {
        if ($nic.TcpipNetbiosOptions -eq 2) { continue }
        try {
            Invoke-CimMethod -InputObject $nic -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = 2 } -ErrorAction Stop | Out-Null
            $changed++
        }
        catch { }
    }

    Write-Bnqq ('NetBIOS desativado em {0} adaptador(es)' -f $changed) 'OK'
}

function Set-BnqqMsiMode {
    Set-BnqqMsiPriority
}

function Set-BnqqNvidiaMaxPerf {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    $found = 0

    foreach ($key in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
        $desc = (Get-ItemProperty -LiteralPath $key.PSPath -Name DriverDesc -ErrorAction SilentlyContinue).DriverDesc
        if ($desc -notmatch 'NVIDIA') { continue }

        Set-BnqqReg $key.PSPath 'PowerMizerEnable' 1
        Set-BnqqReg $key.PSPath 'PowerMizerLevel' 1
        Set-BnqqReg $key.PSPath 'PowerMizerLevelAC' 1
        Set-BnqqReg $key.PSPath 'PerfLevelSrc' 0x2222
        Set-BnqqReg $key.PSPath 'DisableDynamicPstate' 1
        $found++
        Write-Bnqq ('GPU em performance fixo: {0}' -f $desc) 'OK'
    }

    if ($found -eq 0) {
        Write-Bnqq 'Nenhuma GPU NVIDIA encontrada' 'WARN'
        return
    }

    foreach ($svc in @('NvTelemetryContainer')) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if (-not $s -or $s.StartType -eq 'Disabled') { continue }
        Set-BnqqMeta ('Svc_' + $svc) $s.StartType.ToString()
        try {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
            Write-Bnqq ('Servico desativado: {0}' -f $svc) 'OK'
        }
        catch { }
    }
}

function Set-BnqqPrivacy {
    Set-BnqqReg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-BnqqReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    Set-BnqqReg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
    Set-BnqqReg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-BnqqReg 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' 'AutoDownload' 2
    Set-BnqqReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
    Set-BnqqReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 1
    Set-BnqqReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0

    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    Set-BnqqReg $cdm 'SilentInstalledAppsEnabled' 0
    Set-BnqqReg $cdm 'SystemPaneSuggestionsEnabled' 0
    Set-BnqqReg $cdm 'PreInstalledAppsEnabled' 0
    Set-BnqqReg $cdm 'OemPreInstalledAppsEnabled' 0
    Set-BnqqReg $cdm 'SubscribedContent-338388Enabled' 0
    Set-BnqqReg $cdm 'SubscribedContent-338389Enabled' 0
    Set-BnqqReg $cdm 'SubscribedContent-353698Enabled' 0

    Write-Bnqq 'Copilot, Recall, widgets e sugestoes desativados' 'OK'
}

function Set-BnqqSleepPolicy {
    & powercfg /change standby-timeout-ac 0 2>$null | Out-Null
    & powercfg /change hibernate-timeout-ac 0 2>$null | Out-Null
    & powercfg /change disk-timeout-ac 0 2>$null | Out-Null
    & powercfg /change monitor-timeout-ac 15 2>$null | Out-Null
    Write-Bnqq 'Desktop nunca suspende nem desliga disco' 'OK'
}

function Set-BnqqConditionalServices {
    $printers = @(Get-Printer -ErrorAction SilentlyContinue)
    if ($printers.Count -eq 0) {
        $svc = Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue
        if ($svc -and $svc.StartType -ne 'Disabled') {
            Set-BnqqMeta 'Svc_Spooler' $svc.StartType.ToString()
            Stop-Service -Name 'Spooler' -Force -ErrorAction SilentlyContinue
            Set-Service -Name 'Spooler' -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Bnqq 'Spooler desativado (nenhuma impressora instalada)' 'OK'
        }
    }
    else {
        Write-Bnqq ('Spooler mantido: {0} impressora(s)' -f $printers.Count) 'INFO'
    }

    $bt = @(Get-PnpDevice -Class Bluetooth -Status OK -ErrorAction SilentlyContinue)
    if ($bt.Count -eq 0) {
        foreach ($name in @('bthserv', 'BTAGService', 'BthAvctpSvc')) {
            $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
            if (-not $svc -or $svc.StartType -eq 'Disabled') { continue }
            Set-BnqqMeta ('Svc_' + $name) $svc.StartType.ToString()
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Bnqq ('{0} desativado (sem Bluetooth)' -f $name) 'OK'
        }
    }
    else {
        Write-Bnqq ('Bluetooth mantido: {0} dispositivo(s)' -f $bt.Count) 'INFO'
    }
}
