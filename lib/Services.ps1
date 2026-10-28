$script:ServiceCatalog = @(
    @{ Name = 'DiagTrack'; Risk = 'low'; Area = 'Telemetria'; Desc = 'Connected User Experiences and Telemetry' },
    @{ Name = 'dmwappushservice'; Risk = 'low'; Area = 'Telemetria'; Desc = 'WAP Push Message Routing' },
    @{ Name = 'MapsBroker'; Risk = 'low'; Area = 'Telemetria'; Desc = 'Downloaded Maps Manager' },
    @{ Name = 'RetailDemo'; Risk = 'low'; Area = 'Telemetria'; Desc = 'Retail Demo Service' },
    @{ Name = 'wisvc'; Risk = 'low'; Area = 'Telemetria'; Desc = 'Windows Insider Service' },
    @{ Name = 'WMPNetworkSvc'; Risk = 'low'; Area = 'Midia'; Desc = 'Windows Media Player Network Sharing' },
    @{ Name = 'Fax'; Risk = 'low'; Area = 'Legado'; Desc = 'Fax' },
    @{ Name = 'PhoneSvc'; Risk = 'low'; Area = 'Legado'; Desc = 'Phone Service' },
    @{ Name = 'RemoteRegistry'; Risk = 'low'; Area = 'Legado'; Desc = 'Remote Registry' },
    @{ Name = 'WalletService'; Risk = 'low'; Area = 'Legado'; Desc = 'WalletService' },
    @{ Name = 'SDRSVC'; Risk = 'low'; Area = 'Backup'; Desc = 'Windows Backup' },
    @{ Name = 'icssvc'; Risk = 'low'; Area = 'Rede'; Desc = 'Windows Mobile Hotspot Service' },
    @{ Name = 'lfsvc'; Risk = 'low'; Area = 'Localizacao'; Desc = 'Geolocation Service' },
    @{ Name = 'SEMgrSvc'; Risk = 'low'; Area = 'Legado'; Desc = 'Payments and NFC/SE Manager' },
    @{ Name = 'WpcMonSvc'; Risk = 'low'; Area = 'Legado'; Desc = 'Parental Controls' },
    @{ Name = 'AJRouter'; Risk = 'low'; Area = 'Legado'; Desc = 'AllJoyn Router Service' },
    @{ Name = 'TrkWks'; Risk = 'low'; Area = 'Legado'; Desc = 'Distributed Link Tracking Client' },
    @{ Name = 'WerSvc'; Risk = 'low'; Area = 'Diagnostico'; Desc = 'Windows Error Reporting' },
    @{ Name = 'WdiServiceHost'; Risk = 'low'; Area = 'Diagnostico'; Desc = 'Diagnostic Service Host' },
    @{ Name = 'WdiSystemHost'; Risk = 'low'; Area = 'Diagnostico'; Desc = 'Diagnostic System Host' },
    @{ Name = 'SCardSvr'; Risk = 'low'; Area = 'Legado'; Desc = 'Smart Card' },
    @{ Name = 'WbioSrvc'; Risk = 'low'; Area = 'Biometria'; Desc = 'Windows Biometric Service' },
    @{ Name = 'SensorService'; Risk = 'low'; Area = 'Sensores'; Desc = 'Sensor Service' },
    @{ Name = 'SensrSvc'; Risk = 'low'; Area = 'Sensores'; Desc = 'Sensor Monitoring Service' },
    @{ Name = 'stisvc'; Risk = 'low'; Area = 'Impressao'; Desc = 'Windows Image Acquisition' },
    @{ Name = 'NetTcpPortSharing'; Risk = 'low'; Area = 'Legado'; Desc = 'Net.Tcp Port Sharing' },
    @{ Name = 'Spooler'; Risk = 'medium'; Area = 'Impressao'; Desc = 'Print Spooler (desative se nao usa impressora)' },
    @{ Name = 'bthserv'; Risk = 'medium'; Area = 'Bluetooth'; Desc = 'Bluetooth Support Service' },
    @{ Name = 'BTAGService'; Risk = 'medium'; Area = 'Bluetooth'; Desc = 'Bluetooth Audio Gateway' },
    @{ Name = 'BthAvctpSvc'; Risk = 'medium'; Area = 'Bluetooth'; Desc = 'AVCTP Service' },
    @{ Name = 'XblAuthManager'; Risk = 'medium'; Area = 'Xbox'; Desc = 'Xbox Live Auth Manager' },
    @{ Name = 'XblGameSave'; Risk = 'medium'; Area = 'Xbox'; Desc = 'Xbox Live Game Save' },
    @{ Name = 'XboxNetApiSvc'; Risk = 'medium'; Area = 'Xbox'; Desc = 'Xbox Live Networking' },
    @{ Name = 'XboxGipSvc'; Risk = 'medium'; Area = 'Xbox'; Desc = 'Xbox Accessory Management (controle)' },
    @{ Name = 'WSearch'; Risk = 'medium'; Area = 'Indexacao'; Desc = 'Windows Search' },
    @{ Name = 'SysMain'; Risk = 'medium'; Area = 'Memoria'; Desc = 'SysMain / Superfetch' },
    @{ Name = 'SSDPSRV'; Risk = 'medium'; Area = 'Rede'; Desc = 'SSDP Discovery (UPnP)' },
    @{ Name = 'upnphost'; Risk = 'medium'; Area = 'Rede'; Desc = 'UPnP Device Host' },
    @{ Name = 'NvTelemetryContainer'; Risk = 'low'; Area = 'NVIDIA'; Desc = 'NVIDIA Telemetry Container' },
    @{ Name = 'NvContainerLocalSystem'; Risk = 'medium'; Area = 'NVIDIA'; Desc = 'NVIDIA LocalSystem Container' },
    @{ Name = 'ArmouryCrateService'; Risk = 'low'; Area = 'ASUS'; Desc = 'Armoury Crate Service' },
    @{ Name = 'ROG Live Service'; Risk = 'low'; Area = 'ASUS'; Desc = 'ROG Live Service' },
    @{ Name = 'AsusAppService'; Risk = 'low'; Area = 'ASUS'; Desc = 'ASUS App Service' },
    @{ Name = 'ASUSLinkNear'; Risk = 'low'; Area = 'ASUS'; Desc = 'ASUS Link Near' },
    @{ Name = 'ASUSLinkRemote'; Risk = 'low'; Area = 'ASUS'; Desc = 'ASUS Link Remote' },
    @{ Name = 'ASUSSoftwareManager'; Risk = 'low'; Area = 'ASUS'; Desc = 'ASUS Software Manager' },
    @{ Name = 'ASUSSwitch'; Risk = 'low'; Area = 'ASUS'; Desc = 'ASUS Switch' },
    @{ Name = 'ASUSSystemAnalysis'; Risk = 'low'; Area = 'ASUS'; Desc = 'ASUS System Analysis' },
    @{ Name = 'ASUSSystemDiagnosis'; Risk = 'low'; Area = 'ASUS'; Desc = 'ASUS System Diagnosis' },
    @{ Name = 'com.docker.service'; Risk = 'medium'; Area = 'Docker'; Desc = 'Docker Desktop Service' },
    @{ Name = 'vmcompute'; Risk = 'medium'; Area = 'Hyper-V'; Desc = 'Hyper-V Host Compute Service' },
    @{ Name = 'LxssManager'; Risk = 'medium'; Area = 'Hyper-V'; Desc = 'WSL Manager' },
    @{ Name = 'WinDefend'; Risk = 'never'; Area = 'Seguranca'; Desc = 'Microsoft Defender Antivirus' },
    @{ Name = 'WdNisSvc'; Risk = 'never'; Area = 'Seguranca'; Desc = 'Defender Network Inspection' },
    @{ Name = 'Sense'; Risk = 'never'; Area = 'Seguranca'; Desc = 'Defender ATP' },
    @{ Name = 'vgc'; Risk = 'never'; Area = 'Anticheat'; Desc = 'Riot Vanguard' },
    @{ Name = 'BFE'; Risk = 'never'; Area = 'Rede'; Desc = 'Base Filtering Engine' },
    @{ Name = 'MpsSvc'; Risk = 'never'; Area = 'Rede'; Desc = 'Windows Firewall' },
    @{ Name = 'Dnscache'; Risk = 'never'; Area = 'Rede'; Desc = 'DNS Client' },
    @{ Name = 'Dhcp'; Risk = 'never'; Area = 'Rede'; Desc = 'DHCP Client' },
    @{ Name = 'Audiosrv'; Risk = 'never'; Area = 'Audio'; Desc = 'Windows Audio' },
    @{ Name = 'AudioEndpointBuilder'; Risk = 'never'; Area = 'Audio'; Desc = 'Windows Audio Endpoint Builder' },
    @{ Name = 'Themes'; Risk = 'never'; Area = 'Shell'; Desc = 'Themes' },
    @{ Name = 'RpcSs'; Risk = 'never'; Area = 'Kernel'; Desc = 'Remote Procedure Call' },
    @{ Name = 'DcomLaunch'; Risk = 'never'; Area = 'Kernel'; Desc = 'DCOM Server Process Launcher' },
    @{ Name = 'EventLog'; Risk = 'never'; Area = 'Kernel'; Desc = 'Windows Event Log' },
    @{ Name = 'Schedule'; Risk = 'never'; Area = 'Kernel'; Desc = 'Task Scheduler' },
    @{ Name = 'CryptSvc'; Risk = 'never'; Area = 'Kernel'; Desc = 'Cryptographic Services' }
)

function Get-BnqqServiceCatalog {
    return $script:ServiceCatalog
}

function Get-BnqqServiceAudit {
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($entry in $script:ServiceCatalog) {
        $svc = Get-Service -Name $entry.Name -ErrorAction SilentlyContinue
        if (-not $svc) { continue }

        $rows.Add([pscustomobject]@{
            Name        = $entry.Name
            DisplayName = $entry.Desc
            Area        = $entry.Area
            Risk        = $entry.Risk
            Status      = $svc.Status.ToString()
            StartType   = $svc.StartType.ToString()
        })
    }

    return $rows
}

function Show-BnqqServiceAudit {
    param($Audit)

    Write-Host ''
    Write-Host '  SERVICOS' -ForegroundColor Cyan
    Write-Host ''

    foreach ($risk in @('low', 'medium', 'never')) {
        $group = @($Audit | Where-Object { $_.Risk -eq $risk })
        if ($group.Count -eq 0) { continue }

        $label = switch ($risk) {
            'low' { 'DESATIVAVEIS SEM RISCO' }
            'medium' { 'DESATIVAVEIS SE NAO USAR O RECURSO' }
            'never' { 'NUNCA DESATIVAR' }
        }
        $color = switch ($risk) {
            'low' { 'Green' }
            'medium' { 'Yellow' }
            'never' { 'Red' }
        }

        Write-Host ('  {0}' -f $label) -ForegroundColor $color
        foreach ($svc in $group) {
            $state = if ($svc.Status -eq 'Running') { 'RUN ' } else { 'stop' }
            $mark = if ($svc.Risk -eq 'low' -and $svc.Status -eq 'Running') { '!' } else { ' ' }
            Write-Host ('    {0} [{1}] {2,-26} {3,-12} {4}' -f $mark, $state, $svc.Name, $svc.StartType, $svc.DisplayName) -ForegroundColor Gray
        }
        Write-Host ''
    }

    $candidates = @($Audit | Where-Object { $_.Risk -eq 'low' -and $_.Status -eq 'Running' })
    Write-Host ('  {0} servico(s) de baixo risco rodando' -f $candidates.Count) -ForegroundColor Cyan
    Write-Host ''
}

function Set-BnqqServiceTier {
    param(
        [ValidateSet('low', 'medium')]
        [string]$Tier = 'low'
    )

    $hasPrinter = @(Get-Printer -ErrorAction SilentlyContinue).Count -gt 0
    $hasBluetooth = @(Get-PnpDevice -Class Bluetooth -Status OK -ErrorAction SilentlyContinue).Count -gt 0
    $hasWsl = Test-Path -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    $hasDocker = $null -ne (Get-Service -Name 'com.docker.service' -ErrorAction SilentlyContinue)

    $skip = @{}
    if ($hasPrinter) { $skip['Spooler'] = $true }
    if ($hasBluetooth) {
        $skip['bthserv'] = $true
        $skip['BTAGService'] = $true
        $skip['BthAvctpSvc'] = $true
    }
    if ($hasWsl) {
        $skip['LxssManager'] = $true
        $skip['vmcompute'] = $true
    }
    if ($hasDocker) { $skip['com.docker.service'] = $true }

    $targets = @($script:ServiceCatalog | Where-Object { $_.Risk -eq $Tier })
    $store = @{}
    $changed = 0

    foreach ($entry in $targets) {
        if ($skip.ContainsKey($entry.Name)) {
            Write-Bnqq ('Mantido (recurso em uso): {0}' -f $entry.Name) 'INFO'
            continue
        }

        $svc = Get-Service -Name $entry.Name -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        if ($svc.StartType -eq 'Disabled') { continue }

        $store[$entry.Name] = $svc.StartType.ToString()

        try {
            Stop-Service -Name $entry.Name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $entry.Name -StartupType Disabled -ErrorAction Stop
            Write-Bnqq ('Desativado: {0}  ({1})' -f $entry.Name, $entry.Desc) 'OK'
            $changed++
        }
        catch {
            Write-Bnqq ('Falha: {0}' -f $entry.Name) 'WARN'
        }
    }

    if ($store.Count -gt 0) { Set-BnqqMeta 'Services' $store }
    Write-Bnqq ('{0} servico(s) desativado(s)' -f $changed) 'STEP'
}
