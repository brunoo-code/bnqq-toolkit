# O que cada tweak faz

## Energia e CPU

### `power-plan`
Cria um plano próprio duplicando High Performance (desktop) ou Balanced (notebook).

- Desktop: processador 100%/100%, boost mode agressivo, cooling policy ativo, PCIe ASPM off, USB suspend off, core parking 100%.
- Notebook: em CA processador 100%/100%; em bateria 5%/99%, com ASPM e suspend USB ativos.

**Por quê:** o plano "Ultimate Performance" não é mágica. O ganho vem dos valores específicos, que aqui são explícitos e diferentes para AC e DC.

### `power-throttling-off`
`PowerThrottlingOff=1`. Windows deixa de reduzir clocks de processos em segundo plano por política de eficiência.

**Efeito:** remove micro-stutter em janelas de fundo. **Risco:** maior consumo.

### `core-parking-off` (desktop)
`CPMINCORES=100`. Núcleos nunca são estacionados.

**Efeito:** evita latência de acordar núcleo ocioso. **Risco:** temperatura e consumo maiores. Não aplicado em notebook.

### `win32-priority`
`Win32PrioritySeparation=26`. Aumenta o quantum do processo em primeiro plano.

**Efeito:** menos preempção do jogo pelo sistema. **Risco:** nenhum relevante.

### `mmcss-games`
Categoria `Games` do MMCSS com GPU Priority 8, Priority 6, Scheduling Category High.

**Efeito:** threads de jogo recebem prioridade do agendador multimídia.

## Entrada

### `mouse-accel-off`
`MouseSpeed=0`, thresholds 0, curvas `SmoothMouseXCurve`/`YCurve` planas.

**Efeito:** movimento 1:1, sem aceleração. Essencial em FPS. **Risco:** nenhum. Reversível.

### `usb-power-off`
Desliga `EnhancedPowerManagementEnabled` e `AllowIdleIrpInD3` em dispositivos USB/HID.

**Efeito:** mouse e teclado não entram em D3, evitando atraso de reconexão no primeiro movimento.

### `usb-suspend-off`
Suspensão seletiva USB desligada no plano de energia.

### `keyboard-response`
`Keyboard Response` com `Flags=122` (FilterKeys off), repeat 200/6, bounce 0 e delay 0; `KeyboardDelay=0` e `KeyboardSpeed=31`.

**Efeito:** remove o atraso do FilterKeys e acelera a repetição. Não altera polling do teclado.

### `input-queue` (perfis altos)
`MouseDataQueueSize=20` e `KeyboardDataQueueSize=20`.

**Efeito:** reduz o buffer HID. É o menor valor considerado seguro; pode descartar input sob carga extrema. Exige reboot e tem risco médio.

## Áudio

### `audio-isolation`
Tarefa elevada `BNQQ Audio Isolation` mantém `audiodg.exe` no CPU lógico 5 (máscara `0x20`) com prioridade High; desativa spatial audio global e `PKEY_AudioEndpoint_Disable_SysFx` nos endpoints Render/Capture.

**Efeito:** tira o processamento de áudio do thread lógico do jogo e remove enhancements/spatial. `audiodg` é protegido; a tarefa precisa ser elevada. `revert` remove a tarefa e libera o processo.

## Rede

### `qos-dscp`
Políticas locais em `HKLM\SOFTWARE\Policies\Microsoft\Windows\QoS` para `cs2.exe` e `VALORANT-Win64-Shipping.exe`, UDP, DSCP 46 (EF), sem throttle.

**Efeito:** marca os pacotes para prioridade se o roteador/caminho respeitar EF. Não reduz latência física e não garante prioridade fim a fim. A política é lida no boot ou após `gpupdate /force`.

### `network-throttling`
`NetworkThrottlingIndex=0xFFFFFFFF`, `SystemResponsiveness=0`.

**Efeito:** Windows para de limitar pacotes de aplicações multimídia. **Risco:** nenhum.

### `network-adapter`
Desliga Interrupt Moderation, Energy-Efficient Ethernet, Green Ethernet, Flow Control e Wake-on no adaptador físico.

**Efeito:** Interrupt Moderation é o item que realmente adiciona latência — ele agrupa interrupções para poupar CPU. Desligado, cada pacote é processado imediatamente.

## Pro-Tier

### `pro -ProTierAction apply`
Aplica `NetworkThrottlingIndex=0xFFFFFFFF`, `SystemResponsiveness=0`, USB selective suspend AC/DC=0 e `bcdedit /set disabledynamictick Yes`.

**Efeito:** remove limites de rede/MMCSS e micro-suspensão USB; dynamic tick reduz interrupções de timer. **Custo:** dynamic tick pode reduzir FPS no Windows 11 e afeta AC/DC; é opt-in. Reverta com `pro -ProTierAction remove`.

## God-Tier

### `god -GodAction apply`
Aplica `DisablePagingExecutive=1`, `Win32PrioritySeparation=0x26`, CFG desativado por jogo (`cs2.exe`/`VALORANT-Win64-Shipping.exe`) e FSO `~ DISABLEDXMAXIMIZEDWINDOWEDMODE`.

**Efeito:** kernel/drivers residentes em RAM, quantum de foreground e CFG por jogo. **Custo:** CFG por jogo reduz mitigação de exploits e é opt-in por risco de anti-cheat; `god remove` reabilita. O tamanho do shader cache NVIDIA não tem DWORD suportado em `nvlddmkm`; o módulo audita os caches e não injeta valor inventado.

## Sistema

### `gamedvr-off` / `gamemode-on`
Game DVR desligado (sem gravação em background) e Game Mode ligado (prioriza o jogo).

### `fast-startup-off`
`HiberbootEnabled=0`. O desligamento passa a ser completo.

**Efeito:** evita estado de driver inconsistente entre sessões. **Custo:** boot alguns segundos mais lento.

### `hibernate-off` (desktop)
`powercfg /hibernate off`. Libera `hiberfil.sys` e desativa a hibernação.

### `visual-effects`
Efeitos visuais em "melhor desempenho", animações de menu e barra desligadas.

**Efeito:** menos trabalho do DWM na composição. Ganho pequeno, mas sem custo.

### `telemetry-off`
`AllowTelemetry=0`. Reduz atividade de rede e disco em background.

### `startup-trim`
Remove apenas `MicrosoftEdgeAutoLaunch_*` da inicialização. É o único item que o toolkit remove sem perguntar, por ser sempre dispensável.

### `pagefile-managed`
Se o pagefile estiver desativado, volta para gerenciamento automático.

**Por quê:** sem pagefile o Windows faz trim agressivo de working set e alguns anticheats falham.

### `memory-compression-off` (16 GB+)
Desativa a compressão de memória.

**Efeito:** menos CPU gasta comprimindo. **Custo:** mais RAM usada. Só faz sentido com folga de memória.

### `services-low`
Lista fixa de serviços dispensáveis: telemetria, fax, wallet, geolocalização, sensores, diagnóstico, backup do Windows, compartilhamento de mídia.

Nunca inclui: Defender, firewall, áudio, RPC, DCOM, Event Log, Task Scheduler, DNS, DHCP.

## GPU

### `hags-on` (build 22000+)
`HwSchMode=2`. Agendamento de GPU por hardware.

**Efeito:** reduz overhead de submissão na GPU. Em algumas combinações de driver o ganho é nulo — vale medir.

### `fse-forced`
Força comportamento de fullscreen exclusivo via GameDVR FSE behavior.

**Efeito:** evita composição do DWM em borderless.

### GPU state lock (watcher)
`nvidia-smi -i 0 -lgc <max>,<max>` ao detectar o jogo; `-rgc` ao fechar.

**Efeito:** mantém a faixa de clock no máximo durante a partida e libera em idle. O clock instantâneo pode ficar abaixo do máximo por power/thermal; não é garantia de FPS.

## Segurança

### `hvci-off` (desktop)
Desativa Core Isolation / HVCI.

**Efeito:** remove overhead de virtualização em cada syscall — tipicamente 3–10% de CPU em jogos limitados por CPU. **Risco:** perda de proteção contra exploits de kernel. Requer reboot.

### `defender-exclusions`
Exclui pastas de jogos da varredura em tempo real.

**Efeito:** evita que o antivírus inspecione cada leitura de asset durante o jogo. **Risco:** arquivos nessas pastas não são verificados em tempo real.

## Debloat e servicos

### `services-medium`
Servicos de medio risco, aplicados **somente** se o hardware correspondente nao existir: Spooler (sem impressora), Bluetooth (sem radio BT), WSL e Docker (sem instalacao detectada).

**Efeito:** menos threads e handles em background. **Risco:** se voce instalar uma impressora depois, reative o Spooler.

### `sysmain-off` (somente HDD)
Desliga o SysMain apenas em disco mecanico.

**Por que:** em HDD o prefetch ajuda; em SSD ele compete por I/O. Por isso a condicao e invertida em relacao ao que muitos packs fazem.

### `debloat-appx`
Remove uma lista curada de apps pre-instalados (jogos, noticias, clima, mapas, solitaire, Skype, OneNote, Teams consumer, etc.). Nao toca em Store, Calculator, Photos, Camera, Explorer.

### `tasks-off`
Desativa tarefas de telemetria e diagnostico por **prefixo de caminho**, nao por nome exato. Isso funciona em builds onde o nome real tem sufixo (ex.: `Microsoft Compatibility Appraiser Exp`).

### `features-off`
Desativa recursos opcionais nao usados: Work Folders, Simple TCP, TFTP, Printing XPS, Media Playback, Recall.

### `filesystem-tune`
`NtfsDisableLastAccessUpdate=1`, `NtfsMemoryUsage=2`.

**Efeito:** menos escritas de metadados e cache NTFS maior.

### `kernel-memory`
`DisablePagingExecutive=1` e dump de kernel reduzido.

**Efeito:** driver e kernel permanecem em RAM. **Custo:** ~100 MB de RAM. Requer reboot.

### `msi-mode`
Forca interrupcoes em modo MSI (message-signaled) em GPU e adaptador de rede.

**Efeito:** interrupcoes por mensagem tem menos overhead que IRQ compartilhada. **Risco:** driver antigo pode nao suportar — teste antes.

### `nvidia-max-perf` (somente NVIDIA)
Preferencia global por desempenho maximo, telemetria e serviços de container desligados.

### `privacy-lockdown`
Copilot, Recall, widgets, sugestoes e "experiencias personalizadas" desativados.

## GPU e display

### `gpu-preference`
Grava `GpuPreference=2` (High performance) em `HKCU\Software\Microsoft\DirectX\UserGpuPreferences` para cada executável de jogo encontrado.

**Efeito:** em notebook com iGPU + dGPU, o Windows deixa de escolher o vídeo integrado. É a diferença entre 30 e 120 FPS em alguns notebooks.

### `display-optimizations`
`DirectXUserGlobalSettings` com `VRROptimizeEnable=1` e `SwapEffectUpgradeEnable=1`.

**Efeito:** VRR gerenciado pelo DirectX e swap chain moderna em jogos de janela. Não muda nada em fullscreen exclusivo.

### `defender-cpu-limit`
`ScanAvgCPULoadFactor=20` (padrão 50).

**Efeito:** a varredura em background nunca passa de 20% de CPU. Evita pico de 100% no meio da partida.

## CPU (perfil `extreme`)

### `mitigations-off`
`FeatureSettingsOverride=3` e `FeatureSettingsOverrideMask=3`.

**Efeito:** desliga as mitigações em software de Spectre/Meltdown. Em AMD Zen e Intel mais antigos, 5–15% de CPU em jogos CPU-bound. **Risco:** exposição a exploits de CPU. Requer reboot.

### `cstates-off`
`IDLEDISABLE=1` no plano de energia.

**Efeito:** núcleos não entram em C-state profundo. Não aumenta FPS médio, mas corta o stutter do primeiro input depois de ociosidade. **Custo:** consumo e temperatura em idle.

## Memoria

### `large-system-cache` (16 GB+)
`LargeSystemCache=1`.

**Efeito:** cache de arquivos do kernel maior. Com folga de RAM é inofensivo; o ganho em jogos é marginal.

## Durante o jogo

### `focus`
Detecta o jogo em execucao, suspende navegadores, sincronizadores de nuvem, launchers e apps de mensagem, coloca Discord/Spotify/Steam webhelper em prioridade baixa, sobe o jogo para High e I/O High, e ativa o plano BNQQ.

**Por que:** e o que Game Boosters pagos fazem, mas aqui e transparente e reversivel. `unfocus` retoma exatamente o que foi suspenso.

### `rebalance` (ProBalance)
Amostra CPU por processo a cada 1,5 s. Se um processo em background passa de 15% por 3 amostras, cai para BelowNormal e I/O Low. Volta ao normal quando esfria. Nunca toca no processo em primeiro plano.

### `trim`
`EmptyWorkingSet` em processos ociosos com mais de 150 MB.

**Efeito:** libera working set sem matar nada. **Custo:** o app re-lê do disco na proxima interacao. Util em 8 GB.

### `stress`
Carga em todas as threads por 15 s e comparacao entre performance de pico e media.

**Efeito:** mostra queda real de boost. Acima de 12% de queda ha throttling termico ou limite de VRM.

### `stability`
Carga sintética em todas as threads por 3–5 min e auditoria de eventos WHEA 18/19.

**Efeito:** valida Curve Optimizer/undervolt. Evento novo aborta e pede para reduzir o CO; sem evento, confirma estabilidade sob carga. Não substitui horas de jogo.

### `timer`
O watcher solicita `NtSetTimerResolution(5000)` durante o jogo e libera ao fechar. A chamada é feita no processo do watcher, sem injeção no jogo. `.\bnqq.ps1 timer` mostra o valor atual.

## Como verificar se funcionou

Não confie em sensação. Meça antes e depois:

- `.\bnqq.ps1 scan` — estado objetivo
- Latência de DPC: Windows Performance Recorder + Windows Performance Analyzer
- Frametime e latência de apresentação: PresentMon (Intel, open source)
- Clock real da CPU: `Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation`

Se a métrica não mudou, reverta. O objetivo não é aplicar tweaks, é ganhar desempenho.
