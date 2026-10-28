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

## Rede

### `network-throttling`
`NetworkThrottlingIndex=0xFFFFFFFF`, `SystemResponsiveness=10`.

**Efeito:** Windows para de limitar pacotes de aplicações multimídia. **Risco:** nenhum.

### `network-adapter`
Desliga Interrupt Moderation, Energy-Efficient Ethernet, Green Ethernet, Flow Control e Wake-on no adaptador físico.

**Efeito:** Interrupt Moderation é o item que realmente adiciona latência — ele agrupa interrupções para poupar CPU. Desligado, cada pacote é processado imediatamente.

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

## Segurança

### `hvci-off` (desktop)
Desativa Core Isolation / HVCI.

**Efeito:** remove overhead de virtualização em cada syscall — tipicamente 3–10% de CPU em jogos limitados por CPU. **Risco:** perda de proteção contra exploits de kernel. Requer reboot.

### `defender-exclusions`
Exclui pastas de jogos da varredura em tempo real.

**Efeito:** evita que o antivírus inspecione cada leitura de asset durante o jogo. **Risco:** arquivos nessas pastas não são verificados em tempo real.

## Como verificar se funcionou

Não confie em sensação. Meça antes e depois:

- `.\bnqq.ps1 scan` — estado objetivo
- Latência de DPC: Windows Performance Recorder + Windows Performance Analyzer
- Frametime e latência de apresentação: PresentMon (Intel, open source)
- Clock real da CPU: `Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation`

Se a métrica não mudou, reverta. O objetivo não é aplicar tweaks, é ganhar desempenho.
