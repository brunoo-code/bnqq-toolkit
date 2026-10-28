$script:Verdicts = @(
    @{ Id = 'hvci-off'; Verdict = 'proven'; Impact = '3-10% CPU'; Why = 'Cada syscall passa por validacao de integridade no hypervisor. Medido em jogos CPU-bound.' }
    @{ Id = 'credential-guard-off'; Verdict = 'proven'; Impact = '1-4% CPU'; Why = 'Mesmo hypervisor do VBS. Desligar os dois remove a camada de virtualizacao.' }
    @{ Id = 'hypervisor-off'; Verdict = 'proven'; Impact = '2-8% CPU'; Why = 'Remove o hypervisor do boot. Custo: WSL2 e Docker param de funcionar.' }
    @{ Id = 'power-plan'; Verdict = 'proven'; Impact = 'ate 20%'; Why = 'PROCTHROTTLEMAX abaixo de 100 corta boost. E o item de maior impacto isolado.' }
    @{ Id = 'power-throttling-off'; Verdict = 'proven'; Impact = '1-5%'; Why = 'Windows reduz clocks de processos em background por politica de eficiencia.' }
    @{ Id = 'core-parking-off'; Verdict = 'proven'; Impact = '1-3% / menos stutter'; Why = 'Acordar nucleo estacionado custa 10-15 ms no primeiro uso.' }
    @{ Id = 'mouse-accel-off'; Verdict = 'proven'; Impact = 'consistencia'; Why = 'Curva de aceleracao torna o movimento dependente da velocidade. 1:1 e pre-requisito.' }
    @{ Id = 'usb-power-off'; Verdict = 'proven'; Impact = '1-3 ms'; Why = 'Dispositivo em D3 precisa acordar antes de entregar o primeiro pacote HID.' }
    @{ Id = 'network-adapter'; Verdict = 'proven'; Impact = '0.5-2 ms'; Why = 'Interrupt Moderation agrupa interrupcoes de rede para poupar CPU.' }
    @{ Id = 'network-throttling'; Verdict = 'proven'; Impact = '0-2 ms'; Why = 'NetworkThrottlingIndex limita pacotes de aplicacoes multimidia.' }
    @{ Id = 'gamedvr-off'; Verdict = 'proven'; Impact = '1-4%'; Why = 'Captura em segundo plano consome GPU e disco mesmo sem gravar.' }
    @{ Id = 'defender-exclusions'; Verdict = 'proven'; Impact = 'carregamento'; Why = 'Varredura em tempo real inspeciona cada leitura de asset do jogo.' }
    @{ Id = 'fullscreen-opt'; Verdict = 'proven'; Impact = '5-15 ms'; Why = 'Borderless passa pelo DWM, que adiciona composicao e pode limitar a 60 Hz.' }
    @{ Id = 'fse-forced'; Verdict = 'proven'; Impact = '5-15 ms'; Why = 'Forca o caminho de fullscreen exclusivo quando o jogo nao pede.' }
    @{ Id = 'timer-defaults'; Verdict = 'proven'; Impact = 'ate 141 FPS'; Why = 'useplatformclock/disabledynamictick sao placebo no Win11 e podem derrubar FPS. Remove-los restaura o TSC.' }
    @{ Id = 'background-apps-off'; Verdict = 'proven'; Impact = 'RAM/CPU'; Why = 'Apps UWP mantem processos vivos em background por padrao.' }
    @{ Id = 'debloat-appx'; Verdict = 'proven'; Impact = 'RAM/disco'; Why = 'Apps pre-instalados rodam tarefas e atualizacoes em background.' }
    @{ Id = 'tasks-off'; Verdict = 'proven'; Impact = 'I/O'; Why = 'Compatibilidade, telemetria e WinSAT acordam em horarios aleatorios.' }
    @{ Id = 'startup-trim'; Verdict = 'proven'; Impact = 'boot/RAM'; Why = 'Cada item de startup e um processo residente.' }
    @{ Id = 'startup-launchers'; Verdict = 'proven'; Impact = 'RAM/CPU'; Why = 'Launchers e updaters ficam residentes sem necessidade.' }
    @{ Id = 'services-low'; Verdict = 'proven'; Impact = 'RAM/CPU'; Why = 'Servicos de telemetria, fax, wallet e sensores nao tem funcao em gaming.' }
    @{ Id = 'services-medium'; Verdict = 'proven'; Impact = 'RAM/disco'; Why = 'Indexacao, Xbox e UPnP competem por CPU e disco.' }
    @{ Id = 'conditional-services'; Verdict = 'proven'; Impact = 'RAM/CPU'; Why = 'Spooler e Bluetooth so fazem sentido se existir impressora/dispositivo.' }
    @{ Id = 'keyboard-response'; Verdict = 'proven'; Impact = 'QoL'; Why = 'Delay de repeticao padrao e ~500 ms. Afeta buy menu e binds.' }
    @{ Id = 'nvidia-max-perf'; Verdict = 'likely'; Impact = '0-5%'; Why = 'Evita downclock do GPU entre frames. Custo: consumo em idle.' }
    @{ Id = 'hags-on'; Verdict = 'likely'; Impact = '0-5%'; Why = 'Reduz overhead de submissao. Ganho depende do driver e do jogo.' }
    @{ Id = 'msi-mode'; Verdict = 'likely'; Impact = '0.5-2 ms'; Why = 'Interrupcoes por mensagem evitam compartilhamento de linha IRQ.' }
    @{ Id = 'pcie-aspm-off'; Verdict = 'likely'; Impact = '0.5-2 ms'; Why = 'ASPM coloca o link PCIe em estado de baixo consumo.' }
    @{ Id = 'usb-suspend-off'; Verdict = 'likely'; Impact = '1-3 ms'; Why = 'Suspensao seletiva desliga a porta USB apos ociosidade.' }
    @{ Id = 'usb3-lpm-off'; Verdict = 'likely'; Impact = '0-1 ms'; Why = 'Link Power Management do USB 3 reduz a taxa do link.' }
    @{ Id = 'mmcss-games'; Verdict = 'likely'; Impact = '0-2%'; Why = 'Prioriza threads do jogo no agendador multimidia.' }
    @{ Id = 'win32-priority'; Verdict = 'likely'; Impact = '0-2%'; Why = 'Aumenta o quantum do processo em primeiro plano.' }
    @{ Id = 'process-priority'; Verdict = 'likely'; Impact = '0-2%'; Why = 'IFEO eleva prioridade do jogo e rebaixa overlays.' }
    @{ Id = 'steam-overlay-off'; Verdict = 'likely'; Impact = '0-2%'; Why = 'Overlay injeta hooks no processo do jogo.' }
    @{ Id = 'discord-tweaks'; Verdict = 'likely'; Impact = '0-3%'; Why = 'Aceleracao de hardware do Discord disputa a GPU com o jogo.' }
    @{ Id = 'browser-background-off'; Verdict = 'likely'; Impact = 'RAM/CPU'; Why = 'Background mode mantem processos do navegador vivos.' }
    @{ Id = 'memory-compression-off'; Verdict = 'likely'; Impact = '0-2% CPU'; Why = 'Comprimir paginas gasta CPU. So vale com folga de RAM.' }
    @{ Id = 'kernel-memory'; Verdict = 'likely'; Impact = '0-1%'; Why = 'Mantem o kernel residente, evitando page-out de codigo critico.' }
    @{ Id = 'filesystem-tune'; Verdict = 'likely'; Impact = 'I/O'; Why = 'Last access gera escrita de metadados a cada leitura.' }
    @{ Id = 'tcp-tuning'; Verdict = 'likely'; Impact = 'jitter'; Why = 'ECN e timestamps podem gerar retransmissoes desnecessarias.' }
    @{ Id = 'delivery-opt-off'; Verdict = 'likely'; Impact = 'upload'; Why = 'P2P de atualizacoes envia dados para outros PCs.' }
    @{ Id = 'fast-startup-off'; Verdict = 'likely'; Impact = 'estabilidade'; Why = 'Hiberboot reaproveita estado de driver entre sessoes.' }
    @{ Id = 'ndu-off'; Verdict = 'proven'; Impact = 'corrige leak'; Why = 'Driver Ndu tem vazamento de memoria conhecido em builds antigos.' }
    @{ Id = 'mpo-off'; Verdict = 'likely'; Impact = 'corrige stutter'; Why = 'MPO causa flicker/stutter em algumas combinacoes NVIDIA + monitor.' }
    @{ Id = 'pagefile-fixed'; Verdict = 'likely'; Impact = 'estabilidade'; Why = 'Sem pagefile o Windows faz trim agressivo e anticheats podem falhar.' }
    @{ Id = 'gamemode-on'; Verdict = 'likely'; Impact = '0-2%'; Why = 'Evita que Windows Update e manutencao rodem durante a partida.' }
    @{ Id = 'telemetry-off'; Verdict = 'likely'; Impact = 'background'; Why = 'Reduz atividade de rede e disco.' }
    @{ Id = 'privacy-lockdown'; Verdict = 'neutral'; Impact = '0%'; Why = 'Sugestoes e widgets nao rodam durante o jogo. Vale por limpeza.' }
    @{ Id = 'visual-effects'; Verdict = 'neutral'; Impact = '0-1%'; Why = 'DWM ja e acelerado. Ganho perceptivel apenas em GPU muito fraca.' }
    @{ Id = 'hibernate-off'; Verdict = 'neutral'; Impact = '0%'; Why = 'Nao afeta FPS. Libera espaco em disco.' }
    @{ Id = 'reserved-storage-off'; Verdict = 'neutral'; Impact = '0%'; Why = 'Apenas libera ~7 GB. Nao afeta desempenho.' }
    @{ Id = 'netbios-off'; Verdict = 'neutral'; Impact = '0%'; Why = 'Reduz broadcast em rede local. Nao afeta jogos online.' }
    @{ Id = 'dns-fast'; Verdict = 'neutral'; Impact = 'login'; Why = 'Afeta resolucao de nomes (login/loja), nao a latencia in-game.' }
    @{ Id = 'sleep-policy'; Verdict = 'neutral'; Impact = '0%'; Why = 'Evita suspensao durante downloads longos.' }
    @{ Id = 'features-off'; Verdict = 'neutral'; Impact = 'seguranca'; Why = 'Reduz superficie de ataque (SMB1, PS2). Nao muda FPS.' }
    @{ Id = 'gpu-preference'; Verdict = 'proven'; Impact = 'evita iGPU'; Why = 'Em notebook com video integrado e dedicado, o Windows pode escolher a iGPU. Forcar High performance garante a dGPU.' }
    @{ Id = 'display-optimizations'; Verdict = 'likely'; Impact = '1-3% / smooth'; Why = 'VRR otimizado e swap chain moderno em jogos de janela reduzem tearing e stutter. Sem efeito em fullscreen exclusivo.' }
    @{ Id = 'defender-cpu-limit'; Verdict = 'proven'; Impact = 'menos picos'; Why = 'Limita a varredura em background a 20% de CPU. Evita picos de 100% durante o jogo.' }
    @{ Id = 'large-system-cache'; Verdict = 'neutral'; Impact = '0-1%'; Why = 'LargeSystemCache=0 prioriza o working set dos jogos sobre o cache de arquivos do kernel. Com 16 GB+ o efeito e marginal, mas e o valor correto para desktop gamer.' }
    @{ Id = 'mitigations-off'; Verdict = 'proven'; Impact = '5-15% CPU'; Why = 'Mitigacoes de Spectre/Meltdown em software custam CPU em cada troca de contexto. Desligar devolve desempenho. Custo: exposicao a exploits de CPU.' }
    @{ Id = 'cstates-off'; Verdict = 'likely'; Impact = 'latencia'; Why = 'Nucleos nao entram em C-state profundo, reduzindo o tempo de wake. Nao aumenta FPS medio, mas corta stutter no primeiro input.' }
    @{ Id = 'interrupt-affinity'; Verdict = 'likely'; Impact = '0.5-2 ms / 1% low'; Why = 'DPC/ISR de GPU, rede e USB deixam de preemptar os nucleos 0-1, onde o thread principal do jogo costuma rodar. Ganho aparece no 0.1% low, nao na media. So em desktop com 8+ threads.' }
    @{ Id = 'ndis-offloads'; Verdict = 'likely'; Impact = '0.3-1.5 ms'; Why = 'Interrupt moderation agrupa pacotes antes de entregar ao kernel. Desligar entrega cada pacote imediatamente. Em notebook o modo agressivo (LSO/Flow Control) e ignorado para nao prejudicar bateria e throughput.' }
    @{ Id = 'rss-tuning'; Verdict = 'likely'; Impact = 'jitter'; Why = 'RSS distribui o processamento de recepcao entre nucleos. Base 4 mantem a pilha de rede fora dos nucleos 0-1. So se aplica quando o driver expoe *RSS.' }
    @{ Id = 'tcp-kernel'; Verdict = 'likely'; Impact = 'jitter'; Why = 'Timestamps e ECN adicionam cabecalho e logica de decisao. Autotuning normal evita crescimento agressivo de janela. DCA/NetDMA so existem em hardware antigo.' }
    @{ Id = 'ntfs-shortnames'; Verdict = 'neutral'; Impact = 'I/O'; Why = 'Nomes 8.3 geram entradas extras na MFT para cada arquivo novo. Nao afeta arquivos ja existentes nem FPS diretamente.' }
    @{ Id = 'etw-autologgers'; Verdict = 'likely'; Impact = '0-1% / I/O'; Why = 'Autologgers de telemetria gravam buffers ETW em disco durante a sessao. Desligar remove escrita e buffer de kernel.' }
    @{ Id = 'bcd-timer'; Verdict = 'likely'; Impact = 'estabilidade'; Why = 'useplatformclock=No forca o TSC, que e o timer correto no Win11. tscsyncpolicy=Enhanced garante sincronia entre nucleos. Nao e o mesmo que o pacote placebo de HPET.' }
    @{ Id = 'browser-choking'; Verdict = 'likely'; Impact = '0-3% GPU'; Why = 'Aceleracao de hardware do navegador mantem contexto grafico e processos de renderer vivos. Desligar libera GPU e reduz disputa por VRAM durante o jogo.' }
    @{ Id = 'shortcut-flags'; Verdict = 'likely'; Impact = '0-2%'; Why = 'Flags de Chromium impedem throttling de timers e renderizacao em segundo plano. O navegador deixa de acordar a CPU enquanto o jogo esta em foco.' }
    @{ Id = 'ai-cleanup'; Verdict = 'proven'; Impact = 'RAM/CPU'; Why = 'Copilot, Recall e tarefas de Application Experience mantem modelos e varreduras residentes. Bloquear remove CPU, disco e memoria de background.' }
    @{ Id = 'gpu-vendor-profile'; Verdict = 'likely'; Impact = '0-5%'; Why = 'NVIDIA: P-state fixo evita downclock entre frames. AMD: ULPS off remove deep sleep e Anti-Lag reduz fila de apresentacao. Custo: consumo em idle.' }
    @{ Id = 'io-queue-depth'; Verdict = 'likely'; Impact = 'I/O'; Why = 'Mais worker threads criticos absorvem picos de leitura assincrona de texturas em NVMe sem serializar no thread pool padrao.' }
    @{ Id = 'ssd-trim'; Verdict = 'proven'; Impact = 'I/O'; Why = 'TRIM devolve blocos livres ao controlador. Sem ele, o SSD precisa apagar blocos durante o carregamento de texturas, gerando picos de latencia.' }
    @{ Id = 'game-watcher'; Verdict = 'proven'; Impact = 'latencia'; Why = 'O plano Ultimate so entra quando o jogo abre e sai quando fecha. Core parking 0, C-states off e min 100% durante a partida, Balanced no resto.' }
    @{ Id = 'game-affinity'; Verdict = 'likely'; Impact = '0.1% low'; Why = 'Pinar o processo nos nucleos fisicos (sem SMT) reduz contencao entre threads de render e siblings. Custo: menos threads efetivas; medir 0.1% low antes/depois.' }
)

$script:Debunked = @(
    @{ Tweak = 'useplatformclock true / disabledynamictick yes'; Why = 'No Windows 11 o timer TSC e escolhido dinamicamente. Forcar modo legado derruba FPS (relatos de -60 a -140 FPS).' }
    @{ Tweak = 'Timer resolution 0.5 ms'; Why = 'Resolucao de timer nao altera FPS nem latencia de input. Nao e um valor fixo.' }
    @{ Tweak = 'TcpAckFrequency / TCPNoDelay (Nagle)'; Why = 'Jogos usam UDP. Nagle so afeta TCP, que o jogo nao usa para gameplay.' }
    @{ Tweak = 'Desativar SysMain em SSD'; Why = 'Em NVMe o impacto e nulo. Em HDD ainda ajuda no boot.' }
    @{ Tweak = 'Desativar HPET no Gerenciador de Dispositivos'; Why = 'Duplicado do BCD. No Win11 e placebo ou prejudicial.' }
    @{ Tweak = 'Limpar standby list antes de jogar'; Why = 'Standby e cache de arquivos. Limpar forca releitura do disco.' }
    @{ Tweak = 'Prioridade Realtime no jogo'; Why = 'Pode travar input e audio do sistema. High e o teto seguro.' }
    @{ Tweak = 'Afinidade fixa em 1-2 nucleos'; Why = 'Impede o scheduler de migrar threads e concentra todo o jogo em poucos nucleos. O pin em todos os nucleos fisicos (game-affinity) e diferente e deve ser medido.' }
    @{ Tweak = 'Desativar SMT'; Why = 'Reduz threads disponiveis. Jogos modernos se beneficiam de SMT.' }
    @{ Tweak = 'Limpeza de registro'; Why = 'Sem ganho mensuravel. Risco de corromper chaves.' }
    @{ Tweak = 'DNS gamer'; Why = 'Nao altera rota nem latencia do servidor do jogo.' }
    @{ Tweak = 'Desativar paginacao por completo'; Why = 'Causa trim de working set e falhas em anticheats.' }
)

function Get-BnqqVerdict {
    param([string]$Id)
    return $script:Verdicts | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
}

function Show-BnqqVerdicts {
    param([string]$Profile, [string]$ConfigPath)

    $catalog = Get-BnqqCatalog
    $ids = if ($Profile) { Get-BnqqProfile -Name $Profile -ConfigPath $ConfigPath } else { @($catalog | ForEach-Object { $_.Id }) }

    Write-Host ''
    Write-Host '  VEREDITO POR TWEAK' -ForegroundColor Cyan
    Write-Host ''

    $order = @('proven', 'likely', 'neutral')
    $labels = @{
        'proven'  = 'COMPROVADO'
        'likely'  = 'PROVAVEL'
        'neutral' = 'NEUTRO'
    }
    $colors = @{
        'proven'  = 'Green'
        'likely'  = 'Yellow'
        'neutral' = 'DarkGray'
    }

    foreach ($v in $order) {
        $group = @($script:Verdicts | Where-Object { $_.Verdict -eq $v -and $ids -contains $_.Id })
        if ($group.Count -eq 0) { continue }

        Write-Host ('  {0}' -f $labels[$v]) -ForegroundColor $colors[$v]
        foreach ($item in $group) {
            $name = ($catalog | Where-Object { $_.Id -eq $item.Id } | Select-Object -First 1).Name
            Write-Host ('    {0,-52} {1}' -f $name, $item.Impact) -ForegroundColor Gray
            Write-Host ('      {0}' -f $item.Why) -ForegroundColor DarkGray
        }
        Write-Host ''
    }

    Write-Host '  NAO FAZER (placebo ou prejudicial)' -ForegroundColor Red
    foreach ($d in $script:Debunked) {
        Write-Host ('    {0}' -f $d.Tweak) -ForegroundColor Gray
        Write-Host ('      {0}' -f $d.Why) -ForegroundColor DarkGray
    }
    Write-Host ''
}
