function New-BnqqFinding {
    param(
        [ValidateSet('critical', 'warn', 'info', 'ok')]
        [string]$Severity,
        [string]$Title,
        [string]$Detail,
        [string]$Fix,
        [string]$Impact = ''
    )

    return [pscustomobject]@{
        Severity = $Severity
        Title    = $Title
        Detail   = $Detail
        Fix      = $Fix
        Impact   = $Impact
    }
}

function Get-BnqqScore {
    param($Findings)

    $score = 100
    foreach ($f in $Findings) {
        switch ($f.Severity) {
            'critical' { $score -= 25 }
            'warn' { $score -= 12 }
            'info' { $score -= 3 }
        }
    }

    if ($score -lt 0) { $score = 0 }
    return $score
}

function Get-BnqqModuleCpu {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $info = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
    $proc = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
    $sys = Get-CimInstance Win32_PerfFormattedData_PerfOS_System -ErrorAction SilentlyContinue

    $scheme = (powercfg /getactivescheme) -join ' '
    $guid = [regex]::Match($scheme, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value

    $minAc = $null
    $maxAc = $null
    $parking = $null
    try {
        $q = (powercfg /query $guid SUB_PROCESSOR PROCTHROTTLEMIN 2>$null) -join ' '
        if ($q -match 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $minAc = [Convert]::ToInt32($Matches[1], 16) }
        $q = (powercfg /query $guid SUB_PROCESSOR PROCTHROTTLEMAX 2>$null) -join ' '
        if ($q -match 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $maxAc = [Convert]::ToInt32($Matches[1], 16) }
        $q = (powercfg /query $guid SUB_PROCESSOR 0cc5b647-c1df-4637-891a-dec35c318583 2>$null) -join ' '
        if ($q -match 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $parking = [Convert]::ToInt32($Matches[1], 16) }
    }
    catch { }

    $findings = New-Object System.Collections.Generic.List[object]
    $perf = if ($info) { [double]$info.PercentProcessorPerformance } else { $null }
    $maxFreq = if ($info) { [double]$info.PercentofMaximumFrequency } else { $null }
    $dpc = if ($proc) { [double]$proc.PercentDPCTime } else { $null }
    $isr = if ($proc) { [double]$proc.PercentInterruptTime } else { $null }
    $queue = if ($sys) { [double]$sys.ProcessorQueueLength } else { $null }

    if ($maxAc -ne $null -and $maxAc -lt 100) {
        $findings.Add((New-BnqqFinding 'critical' ('Processador limitado a {0}%' -f $maxAc) 'O teto de frequencia esta abaixo de 100%, o que corta o boost.' 'Plano de energia com PROCTHROTTLEMAX=100.' 'Ate 20% de FPS em jogos limitados por CPU'))
    }

    if ($parking -ne $null -and $parking -lt 100) {
        $findings.Add((New-BnqqFinding 'warn' ('Core parking em {0}%' -f $parking) 'Nucleos entram em estado de baixo consumo e levam tempo para acordar.' 'Definir CPMINCORES=100.' 'Reduz stutter no primeiro input apos ociosidade'))
    }

    if ($perf -ne $null -and $perf -lt 100) {
        $findings.Add((New-BnqqFinding 'warn' ('CPU a {0}% do clock base' -f $perf) 'O processador nao esta sustentando boost no momento da medicao.' 'Verificar temperatura, VRM e plano de energia.' 'Boost completo vale mais que qualquer tweak de registro'))
    }

    if ($dpc -ne $null -and $dpc -gt 3) {
        $findings.Add((New-BnqqFinding 'critical' ('DPC em {0}%' -f $dpc) 'Tempo alto em deferred procedure calls indica driver problematico.' 'Identificar driver com WPA/xperf e atualizar ou remover.' 'DPC alto causa stutter e input lag'))
    }
    elseif ($dpc -ne $null -and $dpc -gt 1.5) {
        $findings.Add((New-BnqqFinding 'warn' ('DPC em {0}%' -f $dpc) 'Acima do ideal para competitivo.' 'Atualizar drivers de rede, audio e chipset.' 'Pode adicionar 1-3 ms de latencia'))
    }

    if ($queue -ne $null -and $queue -gt 2) {
        $findings.Add((New-BnqqFinding 'warn' ('Fila de CPU em {0}' -f $queue) 'Threads esperando CPU: processo em background competindo.' 'Reduzir servicos e startup.' 'Afeta frametime'))
    }

    if ($cpu -and $cpu.NumberOfCores -lt $cpu.NumberOfLogicalProcessors) {
        $findings.Add((New-BnqqFinding 'ok' 'SMT ativo' ('{0}C/{1}T' -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors) '' 'Mantido: desligar SMT reduz desempenho em jogos modernos'))
    }

    $top = @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('_Total', 'Idle') -and $_.PercentProcessorTime -gt 0 } |
        Sort-Object PercentProcessorTime -Descending | Select-Object -First 5 |
        ForEach-Object { '{0} {1}%' -f ($_.Name -replace '#\d+$', ''), $_.PercentProcessorTime })

    return [pscustomobject]@{
        Module   = 'CPU'
        Score    = Get-BnqqScore $findings
        Findings = $findings
        Metrics  = [pscustomobject]@{
            Name      = $cpu.Name.Trim()
            Cores     = $cpu.NumberOfCores
            Threads   = $cpu.NumberOfLogicalProcessors
            BaseMhz   = $cpu.MaxClockSpeed
            PerfPct   = $perf
            MaxFreq   = $maxFreq
            Dpc       = $dpc
            Isr       = $isr
            Queue     = $queue
            MinState  = $minAc
            MaxState  = $maxAc
            Parking   = $parking
            Top       = $top
        }
    }
}

function Get-BnqqModuleMemory {
    $modules = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $mem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue

    $totalGB = [math]::Round((($modules | Measure-Object Capacity -Sum).Sum) / 1GB, 0)
    $speed = ($modules | Measure-Object Speed -Maximum).Maximum
    $configured = ($modules | Measure-Object ConfiguredClockSpeed -Maximum).Maximum
    $channels = @($modules | ForEach-Object {
        if ($_.DeviceLocator -match '([A-H])\d+$') { $Matches[1] } else { 'X' }
    } | Select-Object -Unique).Count

    $findings = New-Object System.Collections.Generic.List[object]

    if ($channels -lt 2 -and $totalGB -ge 8) {
        $findings.Add((New-BnqqFinding 'critical' 'Memoria em single channel' 'Largura de banda pela metade; em jogos isso corta FPS minimo.' 'Instalar pentes em slots de canais diferentes.' '10-25% no 1% low de jogos CPU-bound'))
    }

    if ($speed -and $configured -and $configured -lt $speed) {
        $findings.Add((New-BnqqFinding 'warn' ('RAM rodando a {0} MT/s (rated {1})' -f $configured, $speed) 'XMP/DOCP/EXPO desligado na BIOS.' 'Ativar perfil XMP/DOCP/EXPO.' '5-15% no 1% low'))
    }

    if ($cs -and -not $cs.AutomaticManagedPagefile) {
        $pf = @(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue)
        if ($pf.Count -eq 0) {
            $findings.Add((New-BnqqFinding 'warn' 'Pagefile desativado' 'Sem pagefile o Windows faz trim agressivo de working set e alguns anticheats falham.' 'Definir pagefile gerenciado ou fixo.' 'Evita stutter por falta de memoria virtual'))
        }
    }

    $mm = $null
    try { $mm = Get-MMAgent -ErrorAction Stop } catch { }

    if ($mm -and $mm.MemoryCompression -and $totalGB -ge 16) {
        $findings.Add((New-BnqqFinding 'info' 'Compressao de memoria ativa' 'Gasta CPU comprimindo paginas.' 'Desativar com folga de RAM.' 'Pequeno: 0-2% de CPU'))
    }

    $standby = if ($mem -and $mem.StandbyCacheNormalPriorityBytes) { [math]::Round($mem.StandbyCacheNormalPriorityBytes / 1GB, 2) } else { $null }
    $avail = if ($mem) { $mem.AvailableMBytes } else { $null }
    $pages = if ($mem) { $mem.PagesPerSec } else { $null }

    if ($pages -ne $null -and $pages -gt 200) {
        $findings.Add((New-BnqqFinding 'warn' ('Pages/s em {0}' -f $pages) 'Sistema paginando: RAM insuficiente para a carga atual.' 'Fechar apps ou aumentar RAM.' 'Paginacao causa stutter severo'))
    }

    if ($standby -ne $null -and $standby -gt 8) {
        $findings.Add((New-BnqqFinding 'info' ('Standby em {0} GB' -f $standby) 'Cache de arquivos; normal e nao prejudica jogos.' 'Nenhuma acao necessaria.' 'Neutro: limpar standby e placebo'))
    }

    $top = @(Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 |
        ForEach-Object { '{0} {1} MB' -f $_.ProcessName, [math]::Round($_.WorkingSet64 / 1MB, 0) })

    return [pscustomobject]@{
        Module   = 'Memoria'
        Score    = Get-BnqqScore $findings
        Findings = $findings
        Metrics  = [pscustomobject]@{
            TotalGB   = $totalGB
            Speed     = $speed
            Configured = $configured
            Channels  = $channels
            StandbyGB = $standby
            AvailableMB = $avail
            PagesSec  = $pages
            Top       = $top
        }
    }
}

function Get-BnqqModuleGpu {
    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'Basic Display|Remote|Virtual' } |
        Sort-Object AdapterRAM -Descending | Select-Object -First 1

    $findings = New-Object System.Collections.Generic.List[object]
    $smi = $null

    if (Test-BnqqCmd 'nvidia-smi') {
        $fields = 'name,driver_version,pstate,clocks.current.graphics,clocks.max.graphics,temperature.gpu,power.draw,power.limit,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max,utilization.gpu,memory.used,memory.total'
        $raw = & nvidia-smi --query-gpu=$fields --format=csv,noheader,nounits 2>$null
        if ($raw) {
            $p = @((($raw -join '') -split ',') | ForEach-Object { $_.Trim() })
            if ($p.Count -ge 15) {
                $smi = [pscustomobject]@{
                    Name = $p[0]; Driver = $p[1]; PState = $p[2]
                    Clock = $p[3]; ClockMax = $p[4]
                    Temp = $p[5]; Power = $p[6]; PowerLimit = $p[7]
                    Gen = $p[8]; GenMax = $p[9]; Width = $p[10]; WidthMax = $p[11]
                    Util = $p[12]; MemUsed = $p[13]; MemTotal = $p[14]
                }
            }
        }
    }

    if ($smi) {
        if ($smi.Gen -ne $smi.GenMax -or $smi.Width -ne $smi.WidthMax) {
            $findings.Add((New-BnqqFinding 'critical' ('PCIe em Gen{0} x{1} (max Gen{2} x{3})' -f $smi.Gen, $smi.Width, $smi.GenMax, $smi.WidthMax) 'A GPU nao esta no link maximo: slot errado, riser ou economia de energia.' 'Usar slot x16 direto na placa-mae e desativar ASPM.' 'Perda de 5-15% em jogos que streamam texturas'))
        }

        if ($smi.PState -ne 'P0' -and [double]$smi.Util -lt 5) {
            $findings.Add((New-BnqqFinding 'info' ('GPU em {0} ociosa' -f $smi.PState) 'Normal em idle; deve ir a P0 sob carga.' 'Nenhuma acao.' 'Neutro'))
        }

        if ([double]$smi.Temp -gt 83) {
            $findings.Add((New-BnqqFinding 'critical' ('GPU a {0} C' -f $smi.Temp) 'Proxima do limite termico: vai reduzir clock.' 'Limpar cooler, trocar pasta, ajustar curva.' 'Throttling custa 10-30% de FPS'))
        }
    }

    $hags = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -ErrorAction SilentlyContinue).HwSchMode
    if ($hags -ne 2 -and [int]$gpu.DriverVersion.Split('.')[0] -ge 30) {
        $findings.Add((New-BnqqFinding 'info' 'HAGS desativado' 'Agendamento de GPU por hardware disponivel.' 'Ativar HwSchMode=2.' '0-5% dependendo do driver'))
    }

    $mpo = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' -Name OverlayTestMode -ErrorAction SilentlyContinue).OverlayTestMode
    if ($mpo -ne 5) {
        $findings.Add((New-BnqqFinding 'info' 'MPO ativo' 'Multiplane overlay pode causar flicker e stutter em algumas GPUs.' 'Ativar OverlayTestMode=5 se houver stutter.' 'Corrige stutter em cenarios especificos'))
    }

    $bar1 = $null
    if (Test-BnqqCmd 'nvidia-smi') {
        $q = (& nvidia-smi -q 2>$null) -join "`n"
        $m = [regex]::Match($q, 'BAR1 Memory Usage[\s\S]{0,200}?Total\s*:\s*(\d+)\s*MiB')
        if ($m.Success) { $bar1 = [int]$m.Groups[1].Value }
    }

    if ($bar1 -and $smi -and $bar1 -lt 1024 -and [int]$smi.MemTotal -ge 6000) {
        $findings.Add((New-BnqqFinding 'warn' ('ReBAR desativado (BAR1 {0} MB)' -f $bar1) 'A GPU expoe apenas 256 MB de BAR.' 'Ativar Resizable BAR / Above 4G na BIOS.' '2-8% em jogos com muitos assets'))
    }

    return [pscustomobject]@{
        Module   = 'GPU'
        Score    = Get-BnqqScore $findings
        Findings = $findings
        Metrics  = [pscustomobject]@{
            Name = if ($smi) { $smi.Name } else { $gpu.Name }
            Driver = if ($smi) { $smi.Driver } else { $gpu.DriverVersion }
            VramMB = if ($smi) { $smi.MemTotal } else { [math]::Round($gpu.AdapterRAM / 1MB, 0) }
            PState = if ($smi) { $smi.PState } else { $null }
            Temp = if ($smi) { $smi.Temp } else { $null }
            Pcie = if ($smi) { 'Gen{0} x{1}' -f $smi.Gen, $smi.Width } else { $null }
            Hags = $hags
            Mpo = $mpo
            Bar1MB = $bar1
        }
    }
}

function Get-BnqqModuleStorage {
    $disks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    $vol = Get-Volume -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
    $perf = Get-CimInstance Win32_PerfFormattedData_PerfDisk_LogicalDisk -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1

    $findings = New-Object System.Collections.Generic.List[object]

    $freePct = if ($vol -and $vol.Size -gt 0) { [math]::Round(($vol.SizeRemaining / $vol.Size) * 100, 1) } else { $null }
    if ($freePct -ne $null -and $freePct -lt 12) {
        $findings.Add((New-BnqqFinding 'warn' ('Disco do sistema com {0}% livre' -f $freePct) 'SSD acima de 85% perde desempenho de escrita e sofre mais desgaste.' 'Liberar espaco.' 'Evita stutter de streaming de texturas'))
    }

    foreach ($d in $disks) {
        if ($d.HealthStatus -ne 'Healthy') {
            $findings.Add((New-BnqqFinding 'critical' ('Disco {0} com saude {1}' -f $d.FriendlyName, $d.HealthStatus) 'Falha iminente ou setores realocados.' 'Backup imediato e substituicao.' 'Risco de perda de dados'))
        }
        if ($d.MediaType -eq 'HDD') {
            $findings.Add((New-BnqqFinding 'warn' ('HDD presente: {0}' -f $d.FriendlyName) 'Jogos em HDD causam stutter de streaming.' 'Mover jogos para SSD.' 'Diferenca de 5-20x em tempo de carregamento'))
        }

        try {
            $rel = Get-StorageReliabilityCounter -PhysicalDisk $d -ErrorAction Stop
            if ($rel.Wear -ne $null -and $rel.Wear -ge 80) {
                $findings.Add((New-BnqqFinding 'warn' ('SSD {0} com {1}% de desgaste' -f $d.FriendlyName, $rel.Wear) 'Proximo do limite de escritas.' 'Planejar substituicao.' 'Evita falha durante uso'))
            }
            if ($rel.Temperature -ne $null -and $rel.Temperature -ge 65) {
                $findings.Add((New-BnqqFinding 'warn' ('SSD {0} a {1} C' -f $d.FriendlyName, $rel.Temperature) 'NVMe acima de 65 C reduz velocidade por throttling.' 'Melhorar ventilacao ou dissipador.' 'Mantem escrita em pico'))
            }
        }
        catch { }
    }

    $trim = (fsutil behavior query DisableDeleteNotify 2>$null) -join ' '
    if ($trim -match 'NTFS.*=\s*1') {
        $findings.Add((New-BnqqFinding 'warn' 'TRIM desativado' 'SSD perde desempenho ao longo do tempo.' 'fsutil behavior set DisableDeleteNotify 0.' 'Mantem escrita do SSD'))
    }

    $queue = if ($perf) { [double]$perf.AvgDiskQueueLength } else { $null }
    if ($queue -ne $null -and $queue -gt 2) {
        $findings.Add((New-BnqqFinding 'warn' ('Fila de disco em {0}' -f $queue) 'I/O de fundo competindo com o jogo.' 'Desativar indexacao e tarefas de telemetria.' 'Reduz stutter de carregamento'))
    }

    return [pscustomobject]@{
        Module   = 'Armazenamento'
        Score    = Get-BnqqScore $findings
        Findings = $findings
        Metrics  = [pscustomobject]@{
            Disks = @($disks | ForEach-Object { '{0} {1}GB {2} {3}' -f $_.FriendlyName, [math]::Round($_.Size / 1GB, 0), $_.MediaType, $_.BusType })
            FreePct = $freePct
            Queue = $queue
            Trim = if ($trim -match '=\s*0') { 'ativo' } else { 'verificar' }
        }
    }
}

function Get-BnqqModuleInput {
    $mouse = (Get-ItemProperty 'HKCU:\Control Panel\Mouse' -ErrorAction SilentlyContinue)
    $kb = (Get-ItemProperty 'HKCU:\Control Panel\Keyboard' -ErrorAction SilentlyContinue)
    $usb = @(Get-PnpDevice -Class USB, HIDClass -Status OK -ErrorAction SilentlyContinue)
    $managed = 0
    foreach ($d in $usb) {
        if (-not $d.InstanceId) { continue }
        $p = 'HKLM:\SYSTEM\CurrentControlSet\Enum\{0}\Device Parameters' -f $d.InstanceId
        $e = (Get-ItemProperty -LiteralPath $p -Name EnhancedPowerManagementEnabled -ErrorAction SilentlyContinue).EnhancedPowerManagementEnabled
        if ($e -ne $null -and $e -ne 0) { $managed++ }
    }

    $findings = New-Object System.Collections.Generic.List[object]

    if ($mouse.MouseSpeed -ne '0') {
        $findings.Add((New-BnqqFinding 'critical' 'Aceleracao do mouse ativa' 'Movimento nao 1:1: imprevisivel em FPS.' 'MouseSpeed=0 e curvas planas.' 'Ganho direto de consistencia na mira'))
    }

    if ($managed -gt 0) {
        $findings.Add((New-BnqqFinding 'warn' ('{0} dispositivo(s) USB com suspensao' -f $managed) 'Portas entram em D3 e adicionam atraso na primeira leitura.' 'Desativar EnhancedPowerManagementEnabled.' 'Evita micro-delay no primeiro movimento'))
    }

    if ($kb.KeyboardDelay -ne '0' -or $kb.KeyboardSpeed -ne '31') {
        $findings.Add((New-BnqqFinding 'info' 'Teclado com repeat lento' 'Delay padrao de ~500 ms para repeticao.' 'KeyboardDelay=0, KeyboardSpeed=31.' 'Melhora resposta em buy menu e binds'))
    }

    $inputs = @(Get-CimInstance Win32_PointingDevice -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })

    return [pscustomobject]@{
        Module   = 'Input'
        Score    = Get-BnqqScore $findings
        Findings = $findings
        Metrics  = [pscustomobject]@{
            MouseSpeed = $mouse.MouseSpeed
            UsbManaged = $managed
            KeyboardDelay = $kb.KeyboardDelay
            KeyboardSpeed = $kb.KeyboardSpeed
            Devices = $inputs
        }
    }
}

function Get-BnqqModuleNetwork {
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
    $findings = New-Object System.Collections.Generic.List[object]
    $net = @()

    foreach ($a in $adapters) {
        $props = @(Get-NetAdapterAdvancedProperty -Name $a.Name -ErrorAction SilentlyContinue)
        $mod = $props | Where-Object { $_.DisplayName -eq 'Interrupt Moderation' } | Select-Object -First 1
        $eee = $props | Where-Object { $_.DisplayName -match 'Energy-Efficient|Green Ethernet' } | Select-Object -First 1

        if ($mod -and $mod.DisplayValue -ne 'Disabled') {
            $findings.Add((New-BnqqFinding 'warn' ('Interrupt Moderation ativo em {0}' -f $a.Name) 'Interrupcoes sao agrupadas para poupar CPU, adicionando latencia.' 'Desativar no adaptador.' '0.5-2 ms de latencia'))
        }
        if ($eee -and $eee.DisplayValue -ne 'Disabled') {
            $findings.Add((New-BnqqFinding 'info' ('EEE ativo em {0}' -f $a.Name) 'Economia de energia no PHY pode introduzir jitter.' 'Desativar.' 'Reduz jitter'))
        }

        $net += [pscustomobject]@{
            Name = $a.Name
            Link = $a.LinkSpeed
            Moderation = if ($mod) { $mod.DisplayValue } else { 'n/d' }
            Eee = if ($eee) { $eee.DisplayValue } else { 'n/d' }
        }
    }

    $ping = @()
    foreach ($target in @('1.1.1.1', '8.8.8.8')) {
        try {
            $r = Test-Connection -ComputerName $target -Count 10 -ErrorAction Stop
            $times = @($r | ForEach-Object { if ($null -ne $_.ResponseTime) { [double]$_.ResponseTime } elseif ($null -ne $_.Latency) { [double]$_.Latency } } | Where-Object { $null -ne $_ })
            if ($times.Count -gt 0) {
                $avg = ($times | Measure-Object -Average).Average
                $diffs = for ($i = 1; $i -lt $times.Count; $i++) { [math]::Abs($times[$i] - $times[$i - 1]) }
                $jitter = if ($diffs.Count -gt 0) { ($diffs | Measure-Object -Average).Average } else { 0 }
                $ping += [pscustomobject]@{ Target = $target; Avg = [math]::Round($avg, 1); Jitter = [math]::Round($jitter, 1); Loss = [math]::Round((1 - $times.Count / 10) * 100, 0) }

                if ($jitter -gt 5) {
                    $findings.Add((New-BnqqFinding 'warn' ('Jitter de {0} ms para {1}' -f [math]::Round($jitter, 1), $target) 'Variacao alta de latencia: pior que ping medio alto.' 'Cabo, porta, roteador e Wi-Fi.' 'Jitter causa desync e teleporte'))
                }
                if ($times.Count -lt 10) {
                    $findings.Add((New-BnqqFinding 'critical' ('Perda de pacotes para {0}' -f $target) 'Perda de pacotes em teste local.' 'Verificar cabo, driver e roteador.' 'Perda e o pior problema de rede para FPS'))
                }
            }
        }
        catch { }
    }

    $tcpLines = @(& netsh int tcp show global 2>$null)
    $ecnLine = $tcpLines | Where-Object { $_ -match 'ECN' } | Select-Object -First 1
    if ($ecnLine -and $ecnLine -match 'enabled') {
        $findings.Add((New-BnqqFinding 'info' 'ECN habilitado' 'Pode gerar retransmissoes em redes que nao suportam.' 'Desativar ecncapability.' 'Reduz picos de latencia'))
    }

    return [pscustomobject]@{
        Module   = 'Rede'
        Score    = Get-BnqqScore $findings
        Findings = $findings
        Metrics  = [pscustomobject]@{
            Adapters = $net
            Ping = $ping
        }
    }
}

function Get-BnqqModuleDisplay {
    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'Basic Display|Remote|Virtual' } |
        Sort-Object AdapterRAM -Descending | Select-Object -First 1
    $monitors = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)

    $findings = New-Object System.Collections.Generic.List[object]

    $refresh = $gpu.CurrentRefreshRate
    $max = $gpu.MaxRefreshRate

    if ($refresh -and $max -and $refresh -lt $max) {
        $findings.Add((New-BnqqFinding 'critical' ('Monitor a {0} Hz, maximo {1} Hz' -f $refresh, $max) 'Taxa de atualizacao abaixo do suportado.' 'Alterar nas configuracoes de video do Windows/NVIDIA.' 'Ganho direto de fluidez e latencia'))
    }
    elseif ($refresh -and $refresh -lt 100) {
        $findings.Add((New-BnqqFinding 'warn' ('Monitor a {0} Hz' -f $refresh) 'Abaixo do ideal competitivo.' 'Verificar taxa maxima no painel da GPU.' '120 Hz+ muda a percepcao de fluidez'))
    }

    $names = @($monitors | ForEach-Object {
        $n = -join [char[]]($_.UserFriendlyName | Where-Object { $_ -ne 0 })
        $m = -join [char[]]($_.ManufacturerName | Where-Object { $_ -ne 0 })
        '{0} {1}' -f $m, $n
    })

    return [pscustomobject]@{
        Module   = 'Display'
        Score    = Get-BnqqScore $findings
        Findings = $findings
        Metrics  = [pscustomobject]@{
            Resolution = '{0}x{1}' -f $gpu.CurrentHorizontalResolution, $gpu.CurrentVerticalResolution
            Refresh = $refresh
            MaxRefresh = $max
            Monitors = $names
        }
    }
}

function Get-BnqqModuleOs {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $findings = New-Object System.Collections.Generic.List[object]

    $vbs = $null
    try {
        $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop
        $vbs = $dg.VirtualizationBasedSecurityStatus
    }
    catch { }

    if ($vbs -eq 2) {
        $findings.Add((New-BnqqFinding 'critical' 'VBS / HVCI ativo' 'Overhead de virtualizacao em chamadas de kernel.' 'Desativar Core Isolation.' '3-10% de CPU em jogos CPU-bound'))
    }

    $dvr = (Get-ItemProperty 'HKCU:\System\GameConfigStore' -Name GameDVR_Enabled -ErrorAction SilentlyContinue).GameDVR_Enabled
    if ($dvr -ne 0) {
        $findings.Add((New-BnqqFinding 'warn' 'Game DVR ativo' 'Captura em segundo plano.' 'Desativar.' 'Remove overhead de captura'))
    }

    $throttle = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Name PowerThrottlingOff -ErrorAction SilentlyContinue).PowerThrottlingOff
    if ($throttle -ne 1) {
        $findings.Add((New-BnqqFinding 'warn' 'Power Throttling ativo' 'Windows reduz clocks de processos em background.' 'Desativar.' 'Evita micro-stutter'))
    }

    $fast = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
    if ($fast -eq 1) {
        $findings.Add((New-BnqqFinding 'info' 'Fast Startup ativo' 'Estado de driver reaproveitado entre sessoes.' 'Desativar.' 'Evita bugs de driver apos desligar'))
    }

    $startup = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue)
    if ($startup.Count -gt 8) {
        $findings.Add((New-BnqqFinding 'warn' ('{0} itens na inicializacao' -f $startup.Count) 'Consomem RAM e CPU no boot.' 'Remover o que nao precisa.' 'Menos processos competindo'))
    }

    $cbs = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $wu = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $pfro = @((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations)
    $driverPending = @($pfro | Where-Object { $_ -match '\.sys$' }).Count -gt 0

    if ($cbs -or $wu -or $driverPending) {
        $findings.Add((New-BnqqFinding 'info' 'Reinicio pendente' 'Ajustes de kernel/driver ainda nao aplicados.' 'Reiniciar.' 'Ativa tweaks pendentes'))
    }

    $bloat = @(Get-BnqqAppxAudit)
    if ($bloat.Count -gt 0) {
        $findings.Add((New-BnqqFinding 'info' ('{0} app(s) de bloat instalados' -f $bloat.Count) 'Apps UWP consomem RAM e rodam em background.' 'Remover com debloat-appx.' 'Libera RAM e reduz atividade'))
    }

    $svcDisabled = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.StartType -eq 'Disabled' }).Count

    $whea = 0
    try {
        $whea = @(Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-WHEA-Logger'
            StartTime    = (Get-Date).AddDays(-7)
        } -ErrorAction Stop).Count
    }
    catch { }

    if ($whea -gt 0) {
        $findings.Add((New-BnqqFinding 'critical' ('{0} erro(s) de hardware (WHEA) em 7 dias' -f $whea) 'Erros corrigiveis de CPU, RAM ou PCIe indicam instabilidade.' 'Rodar memtest e atualizar BIOS.' 'Evita crash e stutter'))
    }

    $bootMs = $null
    try {
        $boot = Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -MaxEvents 30 -ErrorAction Stop |
            Where-Object { $_.Id -eq 100 } | Select-Object -First 1
        if ($boot) {
            $xml = [xml]$boot.ToXml()
            $node = $xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' } | Select-Object -First 1
            if ($node) { $bootMs = [int]$node.'#text' }
        }
    }
    catch { }

    if ($bootMs -ne $null -and $bootMs -gt 45000) {
        $findings.Add((New-BnqqFinding 'warn' ('Boot de {0:N1}s' -f ($bootMs / 1000)) 'Acima de 45 s indica startup ou driver travando o boot.' 'Revisar inicializacao e drivers.' 'Menos tempo ate o jogo abrir'))
    }

    return [pscustomobject]@{
        Module   = 'Sistema'
        Score    = Get-BnqqScore $findings
        Findings = $findings
        Metrics  = [pscustomobject]@{
            Caption = $os.Caption
            Build = $os.BuildNumber
            Vbs = $vbs
            Startup = $startup.Count
            ServicesDisabled = $svcDisabled
            Bloat = $bloat.Count
            Pending = [bool]($cbs -or $wu -or $driverPending)
            Whea = $whea
            BootMs = $bootMs
        }
    }
}

function Get-BnqqModulePower {
    $findings = New-Object System.Collections.Generic.List[object]

    $scheme = (powercfg /getactivescheme) -join ' '
    $plan = [regex]::Match($scheme, '\(([^)]+)\)').Groups[1].Value

    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'Basic Display|Remote|Virtual' } | Select-Object -First 1

    $temp = $null
    try {
        $tz = Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        if ($tz) { $temp = [math]::Round(($tz | Select-Object -First 1).CurrentTemperature / 10 - 273.15, 1) }
    }
    catch { }

    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue

    if ($plan -match 'Economia|Power saver|Balanced|Equilibrado') {
        $findings.Add((New-BnqqFinding 'warn' ('Plano de energia: {0}' -f $plan) 'Pode reduzir clocks sob carga.' 'Usar plano de desempenho.' 'Evita downclock'))
    }

    if ($temp -and $temp -gt 85) {
        $findings.Add((New-BnqqFinding 'critical' ('CPU a {0} C' -f $temp) 'Throttling termico.' 'Limpar cooler e trocar pasta.' 'Perda de 10-30% de clock'))
    }

    if ($battery) {
        $findings.Add((New-BnqqFinding 'info' 'Notebook detectado' 'Perfil deve respeitar bateria.' 'Usar perfil laptop.' 'Evita superaquecimento e consumo'))
    }

    return [pscustomobject]@{
        Module   = 'Energia'
        Score    = Get-BnqqScore $findings
        Findings = $findings
        Metrics  = [pscustomobject]@{
            Plan = $plan
            CpuTemp = $temp
            GpuTemp = $gpu.CurrentTemperature
            Laptop = [bool]$battery
        }
    }
}

function Invoke-BnqqModules {
    $modules = @(
        (Get-BnqqModuleCpu)
        (Get-BnqqModuleMemory)
        (Get-BnqqModuleGpu)
        (Get-BnqqModuleStorage)
        (Get-BnqqModuleInput)
        (Get-BnqqModuleNetwork)
        (Get-BnqqModuleDisplay)
        (Get-BnqqModuleOs)
        (Get-BnqqModulePower)
    )

    $overall = [math]::Round(($modules | Measure-Object Score -Average).Average, 0)

    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($m in $modules) {
        foreach ($f in $m.Findings) {
            if ($f.Severity -in @('critical', 'warn')) {
                $actions.Add([pscustomobject]@{
                    Module   = $m.Module
                    Severity = $f.Severity
                    Title    = $f.Title
                    Fix      = $f.Fix
                    Impact   = $f.Impact
                })
            }
        }
    }

    return [pscustomobject]@{
        Overall = $overall
        Modules = $modules
        Actions = $actions
    }
}

function Show-BnqqModules {
    param($Report)

    Write-Host ''
    Write-Host ('  ANALISE MODULAR  |  SCORE GERAL {0}/100' -f $Report.Overall) -ForegroundColor Cyan
    Write-Host ''

    foreach ($m in $Report.Modules) {
        $color = if ($m.Score -ge 85) { 'Green' } elseif ($m.Score -ge 60) { 'Yellow' } else { 'Red' }
        Write-Host ('  {0,-16} {1,3}/100' -f $m.Module.ToUpper(), $m.Score) -ForegroundColor $color

        foreach ($f in $m.Findings) {
            $mark = switch ($f.Severity) {
                'critical' { 'XX' }
                'warn' { '!!' }
                'info' { '..' }
                default { 'OK' }
            }
            $fcolor = switch ($f.Severity) {
                'critical' { 'Red' }
                'warn' { 'Yellow' }
                'info' { 'DarkGray' }
                default { 'Green' }
            }
            Write-Host ('    [{0}] {1}' -f $mark, $f.Title) -ForegroundColor $fcolor
            if ($f.Detail -and $f.Severity -ne 'ok') {
                Write-Host ('         {0}' -f $f.Detail) -ForegroundColor DarkGray
            }
            if ($f.Impact) {
                Write-Host ('         impacto: {0}' -f $f.Impact) -ForegroundColor DarkCyan
            }
        }
        Write-Host ''
    }

    if ($Report.Actions.Count -gt 0) {
        Write-Host '  ACOES PRIORITARIAS' -ForegroundColor White
        $i = 1
        foreach ($a in ($Report.Actions | Sort-Object @{ Expression = { if ($_.Severity -eq 'critical') { 0 } else { 1 } } } | Select-Object -First 8)) {
            Write-Host ('    {0}. [{1}] {2}' -f $i, $a.Module, $a.Title) -ForegroundColor Gray
            if ($a.Fix) { Write-Host ('       -> {0}' -f $a.Fix) -ForegroundColor DarkCyan }
            $i++
        }
        Write-Host ''
    }
}
