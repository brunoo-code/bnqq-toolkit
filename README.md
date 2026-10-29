# BNQQ Toolkit

Otimizador de latência e estabilidade para Windows, com motor adaptativo: ele **detecta o hardware** e aplica apenas os ajustes que fazem sentido naquele computador. Funciona em desktop e notebook, AMD e Intel, NVIDIA, AMD e Intel.

Nada é aplicado às cegas. Cada tweak tem pré-requisito declarado, efeito documentado e rollback automático.

## Por que este não é mais um pack de registry

Packs tradicionais aplicam a mesma lista em qualquer máquina e vendem placebo. Aqui:

- **Perfis por tier** (`lowend`, `laptop`, `desktop`, `gaming`, `fresh`) escolhidos pelo hardware real
- **Pré-requisitos declarados**: se a condição não bate, o tweak é ignorado e reportado
- **Veredito honesto**: cada tweak é classificado como comprovado, provável ou neutro, com 12 mitos documentados
- **Análise modular com score** por CPU, memória, GPU, disco, input, rede, display, sistema e energia
- **Modo focus** estilo Game Booster: suspende background, prioriza o jogo e restaura depois
- **ProBalance**: rebaixa temporariamente processos que roubam CPU, sem tocar no jogo
- **Stress test**: mede se o boost da CPU se sustenta ou se há throttling térmico
- **Estabilidade PBO**: 3–5 min de carga em todas as threads + auditoria WHEA 18/19 para validar Curve Optimizer
- **Timer dinâmico**: watcher solicita 0,5 ms durante o jogo e libera ao fechar, sem injetar no processo
- **HID e QoS**: Keyboard Response, filas de mouse/teclado e DSCP 46 para CS2/Valorant
- **Áudio isolado**: audiodg em um CPU lógico dedicado com prioridade High e Audio Enhancements off
- **GPU state lock**: watcher trava o clock NVIDIA no máximo durante o jogo e libera com `-rgc`
- **Executável**: `build.ps1` gera `BNQQ_Optimizer.exe` auto-elevado que abre a TUI no console

## Uso

```powershell
# Interativo (menu + deep scan + watcher)
.\bnqq.ps1

# Analisar hardware, BIOS, OS e achados
.\bnqq.ps1 scan

# Score por area com prioridades
.\bnqq.ps1 report

# O que funciona de fato e o que e placebo
.\bnqq.ps1 verdict

# Aplicar perfil automatico (detecta tier e chassi)
.\bnqq.ps1 apply

# Perfis especificos
.\bnqq.ps1 apply -Profile lowend
.\bnqq.ps1 apply -Profile laptop
.\bnqq.ps1 apply -Profile desktop
.\bnqq.ps1 apply -Profile gaming
.\bnqq.ps1 apply -Profile fresh
.\bnqq.ps1 apply -Profile extreme

# Ver o que seria feito
.\bnqq.ps1 apply -WhatIf

# Desfazer
.\bnqq.ps1 revert

# Watcher de jogos (plano Ultimate + afinidade fisica opcional)
.\bnqq.ps1 watch
.\bnqq.ps1 watch -WatcherAction install
.\bnqq.ps1 watch -WatcherAction install -PinPhysical
.\bnqq.ps1 watch -WatcherAction remove
.\bnqq.ps1 watch -WatcherAction run

# Gerar executavel unico com UAC e TUI no console
.\build.ps1
```

Durante a partida:

```powershell
.\bnqq.ps1 focus      # suspende background, sobe prioridade do jogo
.\bnqq.ps1 unfocus    # restaura tudo
.\bnqq.ps1 rebalance  # ProBalance por 60s
.\bnqq.ps1 trim       # libera working set de apps ociosos
```

Diagnóstico:

```powershell
.\bnqq.ps1 status     # resumo do que esta ativo
.\bnqq.ps1 stress     # boost sustentado e throttling
.\bnqq.ps1 stability  # 5 min de carga + WHEA 18/19 (Curve Optimizer)
.\bnqq.ps1 stability -StabilityMinutes 3
.\bnqq.ps1 timer      # timer resolution atual (0.5 ms com watcher)
.\bnqq.ps1 qos        # politicas DSCP 46 e QoS Packet Scheduler
.\bnqq.ps1 audio      # isolamento do audiodg e Audio Enhancements
.\bnqq.ps1 audio -AudioAction install -AudioCore 5
.\bnqq.ps1 audio -AudioAction remove
.\bnqq.ps1 pro        # Pro-Tier: rede, USB suspend e dynamic tick
.\bnqq.ps1 pro -ProTierAction apply
.\bnqq.ps1 pro -ProTierAction remove
.\bnqq.ps1 god        # God-Tier: CFG por jogo, paging e prioridade
.\bnqq.ps1 god -GodAction apply
.\bnqq.ps1 god -GodAction remove
.\bnqq.ps1 vanguard   # Vanguard: IRQ, RSS, DXGI, SMT e standby
.\bnqq.ps1 vanguard -VanguardAction apply
.\bnqq.ps1 ultimate   # Super Pack: IA, servicos, MMCSS e heap
.\bnqq.ps1 ultimate -UltimateAction apply [-RemoveAppx] [-VbsOff]
.\bnqq.ps1 qa         # Stress in-game com engine falsa e watcher
.\bnqq.ps1 acpi       # HPET/TSC e timer ACPI
.\bnqq.ps1 acpi -AcpiAction apply
.\bnqq.ps1 msi        # MSI/PCIe de GPU e rede
.\bnqq.ps1 msi -MsiAction apply
.\bnqq.ps1 bench      # CPU, fila e disco
.\bnqq.ps1 framebench # 60s de frametime, 1% low e 0.1% low no CS2
.\bnqq.ps1 framebench -FrameHotkey F10 -FrameSeconds 60
.\bnqq.ps1 framebench -FrameSkip 10   # descarta o warmup
.\bnqq.ps1 memtune    # status de memoria, kernel e standby
.\bnqq.ps1 memtune -MemoryAction apply   # desliga compressao + kernel em RAM
.\bnqq.ps1 memtune -MemoryAction purge   # limpa a standby list agora
.\bnqq.ps1 memtune -MemoryAction remove  # reverte compressao e paging
.\bnqq.ps1 bcd        # estado do boot
.\bnqq.ps1 guide      # ajustes in-game que dao FPS de verdade
```

## Memoria / kernel / standby

`memtune` concentra o ajuste global de memória (exige elevação para aplicar):

```powershell
.\bnqq.ps1 memtune
.\bnqq.ps1 memtune -MemoryAction apply
.\bnqq.ps1 memtune -MemoryAction purge
.\bnqq.ps1 memtune -MemoryAction remove
```

O `apply` desativa a compressão de memória (`Disable-MMAgent -MemoryCompression`), grava `DisablePagingExecutive=1` em `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management` e faz uma purga inicial da standby list. O paging executive exige **reboot**; desligar a compressão aumenta o consumo de RAM. O `purge` usa `NtSetSystemInformation(SystemMemoryListInformation)` com `SeProfileSingleProcessPrivilege`. O `remove` reativa a compressão e restaura o paging ao padrão.

O watcher faz uma purga ao detectar o jogo e outra a cada **5 minutos** enquanto CS2/Valorant estiver em foco. Com RAM livre abaixo de 4 GB, a purga pode ocorrer a cada 60 s. Standby é cache de arquivos: purgar demais pode causar releitura de disco, por isso não há purga com o jogo em segundo plano nem no boot.

## Frametime e 1% low

`framebench` usa o Intel PresentMon Console para medir o processo do jogo e gerar métricas objetivas:

```powershell
.\bnqq.ps1 framebench
.\bnqq.ps1 framebench -FrameSeconds 60 -FrameSkip 5
.\bnqq.ps1 framebench -FrameHotkey F10 -FrameSeconds 60
```

O comando exige elevação e o jogo aberto. Ele mostra a afinidade/prioridade do processo, descarta os primeiros `FrameSkip` segundos e grava o CSV bruto e um JSON resumido em `reports\framebench-*`. O 1% low é a média dos 1% frames mais lentos; o 0.1% low repete o cálculo com 0.1%. Para comparar ajustes, mantenha a mesma cena, o mesmo percurso e pelo menos 60 segundos por captura.

## Fase 4 — estabilidade, timer, HID e QoS

### Estabilidade PBO (WHEA)

`stability` compila um gerador de carga C# e satura todos os processadores lógicos por 3–5 minutos. O módulo consulta o log `System` por eventos `Microsoft-Windows-WHEA-Logger` IDs **18** e **19** antes/depois da carga. Se aparecer evento novo, a carga é abortada e o aviso é vermelho:

`Instabilidade detectada no Undervolt! Reduza o Curve Optimizer na BIOS (ex: de -15 para -10)`

Sem evento: `Sistema 100% Estável no Curve Optimizer`. Se o Event Viewer não puder ser lido, o veredito é `Indeterminado` — o módulo não presume estabilidade. O JSON fica em `reports/stability-<data>.json`. O teste é sintético; não substitui horas de jogo e não detecta falhas que não gerem WHEA.

### Timer resolution dinâmico

O watcher usa `NtSetTimerResolution(5000, true, ...)` quando detecta `cs2.exe` ou `VALORANT-Win64-Shipping.exe`, e libera a referência quando nenhum jogo resta. A chamada é feita no processo do watcher, **não** no jogo: não há injeção, hook ou driver. O `finally` libera o timer se o watcher for encerrado. `.\bnqq.ps1 timer` mostra o valor atual. Não há tweak de HPET/BCD associado.

### HID

`keyboard-response` grava `Keyboard Response` com `Flags=122` (FilterKeys off), `AutoRepeatDelay=200`, `AutoRepeatRate=6`, `BounceTime=0` e `DelayBeforeAcceptance=0`, além de `KeyboardDelay=0` e `KeyboardSpeed=31`.

`input-queue` reduz as filas `MouseDataQueueSize` e `KeyboardDataQueueSize` de 100 para **20**. É o menor valor considerado seguro; filas menores podem descartar input sob carga extrema. Exige reboot e tem risco médio. Não altera driver, polling rate ou firmware.

### QoS DSCP 46

`qos-dscp` cria políticas locais em `HKLM\SOFTWARE\Policies\Microsoft\Windows\QoS` para `cs2.exe` e `VALORANT-Win64-Shipping.exe`, UDP, DSCP **46** (EF), sem throttle. `.\bnqq.ps1 qos` mostra as políticas e o QoS Packet Scheduler. A política é lida no boot ou após `gpupdate /force`; `Get-NetQosPolicy` pode ficar vazio até lá. DSCP só ajuda se o roteador/caminho respeitar EF; não reduz latência física.

### MPO e HDCP

MPO já é tratado por `OverlayTestMode=5` nos perfis altos. HDCP não possui API/registro público suportado para desativação na NVIDIA; o módulo faz apenas auditoria (`sem controle HDCP suportado`) e não aplica hack não documentado que possa quebrar vídeo/DRM.

## Fase 5 — áudio, GPU state lock e executável

### Áudio isolado

`audio-isolation` desativa o spatial audio global e `PKEY_AudioEndpoint_Disable_SysFx` nos endpoints Render/Capture, e instala a tarefa `BNQQ Audio Isolation`. A tarefa roda elevada no logon e mantém `audiodg.exe` no CPU lógico **5** (máscara `0x20`) com prioridade **High**. O watcher usa CPUs pares (`0x5555`), então o áudio fica no thread ímpar.

```powershell
.\bnqq.ps1 audio
.\bnqq.ps1 audio -AudioAction install -AudioCore 5
.\bnqq.ps1 audio -AudioAction remove
```

`audiodg.exe` é protegido: um shell comum não lê afinidade/prioridade; a tarefa elevada aplica. O `revert` remove a tarefa e libera o processo.

### GPU state lock

O watcher consulta `nvidia-smi --query-gpu=clocks.max.graphics` e, ao detectar CS2/Valorant, executa `nvidia-smi -i 0 -lgc <max>,<max>`; ao fechar, `nvidia-smi -i 0 -rgc`. O `finally` libera o clock no encerramento. Em placas sem `nvidia-smi`, o recurso é ignorado. O lock define a faixa; o clock instantâneo pode ficar abaixo do máximo em idle/power cap. Se o watcher for morto à força, o lock pode persistir até o próximo start/reboot.

### Executável único

`build.ps1` gera `dist\BNQQ_Optimizer.exe` com launcher C# compilado por `csc.exe`, payload ZIP embutido (`bnqq.ps1`, `bnqq-watch.ps1`, `bnqq-audio.ps1`, `lib`, `config`), manifesto `requireAdministrator`, console subsystem e extração versionada em `%LOCALAPPDATA%\BNQQ_Optimizer\<versão>`. A TUI atual é aberta via `powershell.exe`; em erro, o launcher mostra a mensagem e aguarda Enter.

```powershell
.\build.ps1
.\build.ps1 -OutputPath dist\BNQQ_Optimizer.exe
```

O binário não é assinado; o SmartScreen pode avisar. `dist/` fica fora do Git; o `build.ps1` é a fonte reproduzível.

## Pro-Tier — rede e energia

O módulo `lib/ProTier.ps1` concentra ajustes opt-in que não entram nos perfis padrão:

| Ajuste | Valor | Efeito |
|---|---|---|
| `NetworkThrottlingIndex` | `0xFFFFFFFF` | Remove o limite de pacotes multimídia |
| `SystemResponsiveness` | `0` | Não reserva CPU para background durante o jogo |
| USB selective suspend | AC/DC `0` no plano ativo | Evita micro-suspensão da controladora USB |
| `disabledynamictick` | `Yes` (opt-in) | Impede o kernel de parar o timer do processador |

```powershell
.\bnqq.ps1 pro
.\bnqq.ps1 pro -ProTierAction apply
.\bnqq.ps1 pro -ProTierAction remove
```

A opção `[1] Deep Scan` verifica os valores e pergunta se deseja aplicar; a opção `[11]` mostra o painel com aplicar/remover. Exige UAC e reboot.

**Aviso:** `disabledynamictick Yes` pode reduzir FPS no Windows 11; é opt-in, fora dos perfis padrão. O `pro remove` restaura os valores padrão de rede/USB e libera o dynamic tick. Dynamic tick afeta AC e DC; em notebook, avalie o custo de bateria.

## God-Tier — kernel e CFG

Módulo opt-in `lib/GodTier.ps1`:

| Item | Implementação |
|---|---|
| CFG por jogo | `Set-ProcessMitigation` para `cs2.exe` e `VALORANT-Win64-Shipping.exe` |
| FSO | `~ DISABLEDXMAXIMIZEDWINDOWEDMODE` nas Layers |
| Paging | `DisablePagingExecutive=1` |
| Prioridade | `Win32PrioritySeparation=0x26` (38) |

```powershell
.\bnqq.ps1 god
.\bnqq.ps1 god -GodAction apply
.\bnqq.ps1 god -GodAction remove
```

CFG é desativado somente nos dois jogos, nunca globalmente; é opt-in por risco de anti-cheat/segurança. O `god remove` reabilita CFG e volta a prioridade para 26 decimal.

**Shader cache:** não há DWORD público/suportado em `nvlddmkm` para tamanho; o controle fica no NVIDIA App/perfil do driver. O módulo audita `DXCache`, `GLCache` e `D3DSCache` e não injeta valor inventado; o `cache` limpa os caches.

O `[1] Deep Scan` inclui a varredura God-Tier; a TUI pública ganhou `[12]`.

## Vanguard — IRQ, SMT e standby

`lib/Vanguard.ps1` aplica:

| Item | Resultado |
|---|---|
| IRQ GPU | CPU lógico 4 (`0x10`), policy 4, prioridade 3 |
| IRQ rede | CPU lógico 6 (`0x40`), policy 4 |
| Áudio | CPU 5, prioridade High |
| Background | Discord/Chrome/Edge/Spotify/Firefox/Brave nos threads SMT ímpares |
| DXGI/FSO | `SwapEffectUpgradeEnable=1` + FSO por jogo |
| Standby | purga ao detectar o jogo; a cada 5 min em foco; extra abaixo de 4 GB livres |

```powershell
.\bnqq.ps1 vanguard
.\bnqq.ps1 vanguard -VanguardAction apply
```

Em 8C/16T, o jogo usa todos os núcleos físicos; os CPUs 4/6 dos IRQs compartilham o mask do jogo. Isolamento absoluto exigiria reservar núcleos e reduzir o jogo. O Ethernet desta máquina não expõe RSS. `Timer coalescing` não tem API/registro suportado; não foi inventado. `Max Pre-rendered frames`, `Silk Smoothness` e `Threaded Optimization` ficam no perfil do driver/NVIDIA App, não em `nvlddmkm`; nenhuma chave fictícia foi injetada.

A TUI pública ganhou `[13]`; banner **`BNQQ OPTIMIZER v1.0.0`**.

## Licenciamento por Allowlist

O `bnqq.ps1` calcula SHA-256 de `Win32_ComputerSystemProduct.UUID` + `Win32_Processor.ProcessorId` e consulta uma Raw URL de Gist com a lista de HWIDs autorizados. Não existe mais `license.key` na versão pública. Se o HWID nao estiver na lista, o app mostra o HWID e encerra.

## Premium QA

- AMD: `EnableUlps=0` + Anti-Lag via perfil de vendor existente.
- Discord: atalho com `--disable-gpu`; comunicação em prioridade baixa (`CpuPriorityClass=5`, `IoPriority=1`, `PagePriority=1`).
- Rede: checksum offload IP/TCP/UDP v4/v6 e LSO desligados no adaptador físico.
- Energia: idle demote/promote 100 e `IDLEDISABLE=1`.
- Deep Scan `[1]`: QA de IRQ, SMT e timer; em idle informa que o watcher aplicará 0,5 ms no jogo.

## Ultimate — Super Pack e QA in-game

`lib/Ultimate.ps1` cobre IA (Copilot/Recall), Fax/Xbox/Spooler condicional, UWP agressivo (Cortana, BingNews, ZuneVideo, Solitaire, TikTok), perfil MMCSS `BNQQ_Esports`, SharedSection opt-in, VBS/DMA opt-in e lista de serviços. O `WdFilter` **não** é descarregado; a proteção em tempo real é protegida e não deve ser removida.

```powershell
.\bnqq.ps1 ultimate
.\bnqq.ps1 ultimate -UltimateAction apply
.\bnqq.ps1 ultimate -UltimateAction apply -RemoveAppx
.\bnqq.ps1 ultimate -UltimateAction apply -VbsOff
.\bnqq.ps1 qa
```

O `qa` compila um `load.exe` C# de CPU/I/O, inicia um `cs2.exe` controlado e valida timer 0,5 ms, jogo `0x5555`, background `0xAAAA`, detecção do watcher e queda de clock. TUI pública `[14]`; privada `[17]`. Validação de 20 s: clock 4369→4355 MHz, timer 0,500 ms, afinidades OK, veredito **ESTAVEL**; temperatura continua indisponível.

## v1.4.1 — Allowlist em nuvem

A versão pública não usa mais `license.key`. O HWID SHA-256 é consultado em uma Raw URL de Gist:

```powershell
$AllowlistUrl = "COLOQUE_SEU_LINK_AQUI"
```

Se o HWID estiver no texto, a TUI abre. Se não estiver, o app mostra o HWID e encerra para o usuário copiar. O tutorial completo está em `docs/ALLOWLIST.md`.
## v1.4.0 — Silicon / Mitigações / NIC

Versão de auditoria de silício e baixo nível, sem fingir acesso que o Windows não expõe.

- **Mitigações:** `FeatureSettingsOverride=3` e `Mask=3` já estavam presentes. O módulo audita e permite reaplicar com `-DisableMitigations`, mas isso é opt-in e não desliga todo o microcódigo/Retbleed. VBS/HVCI continuam rodando.
- **NVIDIA:** o NVIDIA Profile Inspector não está instalado e não é baixado automaticamente. Não há CLI estável para `Maximum Pre-rendered Frames=1` ou `Threaded Optimization`; nenhuma chave oculta é inventada. O controle real disponível é P-State/clock via `nvidia-smi`.
- **NIC:** o Realtek 2.5GbE já está com `Interrupt Moderation = Disabled`. O módulo garante o estado quando o driver expõe a propriedade.
- **Undervolt:** Ryzen Master, RyzenAdj, Intel XTU e ThrottleStop não estão instalados. Nenhum comando é executado às cegas; o Curve Optimizer atual continua sendo o da BIOS.
- **QA virtual:** motor C# 128 ticks/s, timer 0,500 ms e máscaras `0x5555`/`0xAAAA`.

```powershell
.\bnqq.ps1 silicon
.\bnqq.ps1 silicon -SiliconAction apply
.\bnqq.ps1 silicon -SiliconAction apply -DisableMitigations
.\bnqq.ps1 netqos
```

TUI privada `[29] Silicon`; pública `[26]`.

### Limitações

- `FeatureSettingsOverride` é política do Windows, não desativação de microcódigo.
- Desligar mitigações aumenta risco de segurança; VBS/HVCI não substituem Spectre/Meltdown.
- Sem Profile Inspector/CLI oficial, não há como garantir pre-rendered frames ou threaded optimization.
- Ferramentas de undervolt ausentes não são baixadas nem executadas sem sintaxe validada.
- Interrupt Moderation desativado não garante “hitreg” melhor; pode aumentar carga de CPU.## v1.3.1 — Deep Freeze, Large Pages e P-State

Fase hard-runtime com foco em foco de janela, memória e GPU. VBS/HVCI continuam ligados.

- **Deep Freeze:** watcher suspende processos não essenciais no foco do jogo e retoma ao Alt+Tab ou fechar. Ficam fora por padrão: `explorer`, Riot Client, Vanguard, áudio, DWM e processos de segurança. A lista inclui Steam WebHelper, Discord, navegadores, OneDrive, Dropbox, updaters e launchers.
- **Large Pages:** `SeLockMemoryPrivilege` é concedido via política local; o jogo ainda precisa chamar `VirtualAlloc(MEM_LARGE_PAGES)`. O Windows não força large pages em CS2/Valorant.
- **GPU P-State:** leitura real por `nvidia-smi --query-gpu=pstate`; lock de clock máximo com `nvidia-smi -lgc`. P-State 0 não tem API pública garantida e o NVIDIA Inspector não é baixado automaticamente.
- **Perfis dinâmicos:** working set extra de 192 MB para CS2 e 256 MB para Valorant; watcher registra `E2E` em ms entre foco detectado e QoS/working set/Deep Freeze aplicados.
- **Rede/NDIS:** auditoria de DSCP, `ms_pacer`, regras de firewall e criação opcional de regra UDP outbound dos jogos. O firewall não é desativado; DSCP no fio não é validado sem captura externa.
- **WPR:** `etw -EtwWpr` inicia uma sessão curta do Windows Performance Recorder e salva `.etl` em `reports`, além do sampler leve de DPC/ISR/DWM.

```powershell
.\bnqq.ps1 watch -WatcherAction install -PinPhysical -WatcherDeepFreeze
.\bnqq.ps1 largepages
.\bnqq.ps1 largepages -LargePagesAction apply
.\bnqq.ps1 gpupstate
.\bnqq.ps1 netqos
.\bnqq.ps1 etw -EtwSeconds 15 -EtwWpr
```

TUI privada `[26] Large Pages`, `[27] GPU P-State`, `[28] Rede/DSCP`; pública `[23]/[24]/[25]`.

### Limitações

- Suspender processos pode atrasar Alt+Tab e quebrar apps; Deep Freeze é opt-in e exclui anti-cheat/shell.
- O watcher detecta foco por polling de 1 s quando Deep Freeze está ligado; “instantâneo” não é garantido.
- Large Pages exige suporte da aplicação; conceder o privilégio não altera automaticamente o jogo.
- P-State 0 é observado, não forçado por NVAPI; o clock máximo é o controle real.
- DSCP e firewall não garantem prioridade no roteador.
- WPR é pesado e pode alterar o próprio resultado; use sessões curtas.## v1.3.0 — Runtime Latency, ETW e HID

Fase de runtime, sem reiniciar o Windows para o que é possível aplicar em tempo real. VBS/HVCI continuam obrigatórios e não são contornados.

- **HID/USB:** filas `mouclass`/`kbdclass` mantidas em 20 pacotes (piso seguro para mouse 8 kHz), aceleração off, USB sem suspensão, MSI/prioridade e afinidade nas controladoras PCI USB. A fila de classe é driver de boot: o valor novo só entra no próximo boot.
- **Watcher com foco:** detecta `GetForegroundWindow`; ao focar CS2/Valorant aplica QoS DSCP 46 via `New-NetQosPolicy` no `ActiveStore`, padding de working set do processo e purga de standby ao detectar, a cada 5 min em foco e, com pressão, abaixo de 4 GB livres.
- **ETW/PDH:** `lib/EtwMonitor.ps1` amostra DPC, ISR, interrupções e CPU/working set do DWM; gera JSON em `reports`. É um monitor leve de contadores ETW/PDH, não um ETL completo do WPR.
- **Preflight:** antes de aplicar o perfil `valorant`, valida Secure Boot, TPM, VBS e HVCI; sem conformidade, o perfil é bloqueado.
- **Virtual QA:** motor C# 128 ticks/s, física, memória e loopback, com timer de 0,500 ms e máscaras `0x5555`/`0xAAAA`.

```powershell
.\bnqq.ps1 hid
.\bnqq.ps1 hid -HidAction apply
.\bnqq.ps1 etw -EtwSeconds 15
.\bnqq.ps1 preflight
.\bnqq.ps1 virtualqa -VirtualSeconds 30
```

TUI privada `[23] HID`, `[24] ETW`, `[25] Preflight`; pública `[20]/[21]/[22]`.

### Limitações

- Working set padding mantém páginas mais tempo, mas o Windows ainda pode trimar sob pressão; não é garantia de RAM física permanente.
- QoS DSCP só tem efeito se o caminho de rede respeitar EF; não reduz ping físico.
- ETW/PDH leve não substitui WPR/WPA para análise profunda de DPC/ISR.
- `preflight` exige UAC para ler Secure Boot/TPM.
- Nada de hook, patch de driver ou bypass de anti-cheat.
## v1.2.0 — Compensação VBS/HVCI

Esta versão **mantém VBS e HVCI ligados**. Não existe bypass de estado do Vanguard: o modo `compensate` reduz fontes de latência e organiza CPU, input, rede e GPU sem tocar no anti-cheat.

- **VBS/HVCI:** `hypervisorlaunchtype=auto`, VBS=1 e HVCI=1; reboot obrigatório.
- **Input:** aceleração do mouse off, `MouseHoverTime=0`, filas HID 20, USB sem suspensão e MSI/prioridade nas controladoras PCI USB.
- **Background:** `DiagTrack`, `dmwappushservice`, `WECsvc`, `SysMain` e `WSearch` desativados; standby list purgada.
- **Watcher:** jogo em `0x5555`, background em `0xAAAA`, revalidado a cada 2 s.
- **Virtual QA:** motor C# `lib/VirtualInGameQA.cs`, 128 ticks/s, física, memória e rede loopback; sem jogo real.
- **MSI/ACPI:** GPU/rede com MSI e prioridade; TSC via BCD (`useplatformclock=No`, `tscsyncpolicy=Enhanced`).
- **Power:** core parking off, min/max 100%, idle disable; C-states dependem do firmware AMD.
- **TCP:** `TcpAckFrequency=1` e `TCPNoDelay=1` por interface ativa; aumenta ACKs, não é ideal em todo link.
- **GPU:** HAGS=2; cache de shader continua sob controle do driver (não existe “ilimitado” por registro suportado).

```powershell
.\bnqq.ps1 compensate
.\bnqq.ps1 compensate -CompensateAction apply
.\bnqq.ps1 virtualqa -VirtualSeconds 30
.\bnqq.ps1 apply -Profile valorant
```

TUI privada `[21]/[22]`; pública `[18]/[19]`. O perfil `valorant` não inclui `hvci-off`, `hypervisor-off` ou `credential-guard-off`.

### Limitações honestas

- VBS/HVCI não são desligados; o ganho vem de compensação, não de bypass.
- MSI/afinidade de IRQ não elimina todo o jitter e compartilha núcleos em 8C/16T.
- Desativar `WSearch`/`SysMain` pode piorar busca e cache de arquivos.
- O QA virtual valida timer/afinidade/estabilidade sintética; não substitui um jogo real.
- O cache de shader “ilimitado” não tem chave de registro suportada; o driver decide o tamanho.
## ACPI/HPET e MSI/PCIe

`lib/Acpi.ps1` audita HPET/TSC e aplica `useplatformclock=No` + `tscsyncpolicy=Enhanced` via BCD. A tabela ACPI do firmware **não é editada**; o caminho suportado é selecionar TSC.

`lib/Msi.ps1` varre a árvore PCI, localiza GPU/rede, garante `MSISupported=1`, prioridade 3/2, `DevicePolicy=4` e máscara IRQ (`0x10` GPU / `0x40` rede).

```powershell
.\bnqq.ps1 acpi
.\bnqq.ps1 acpi -AcpiAction apply
.\bnqq.ps1 msi
.\bnqq.ps1 msi -MsiAction apply
```

TUI pública `[16]/[17]`; privada `[19]/[20]`. A HPET física não é desabilitada no Device Manager. Em 8C/16T os IRQs 4/6 compartilham núcleos do jogo.

## Perfis

| Perfil | Alvo | Comportamento |
|---|---|---|
| `lowend` | PC fraco, 4–8 GB, HDD | Prioriza liberar CPU, RAM e disco. Debloat e serviços médios incluídos. |
| `laptop` | Notebook | Respeita bateria: no DC mantém downclock e economia. Não mexe em core parking nem HVCI. NDIS agressivo e afinidade de interrupção são ignorados automaticamente. |
| `desktop` | Desktop | Equilibrado. Sem desligar HVCI. Inclui afinidade de interrupção se houver 8+ threads. |
| `gaming` | Desktop competitivo | Agressivo. HVCI off, core parking off, memory compression off, MSI + prioridade de interrupção, filas HID 20, QoS DSCP 46 e áudio isolado (71). |
| `fresh` | Pós-formatação | Tudo do `gaming` + remoção do hypervisor no boot + RSS, TCP kernel, NTFS 8.3, ETW autologgers, BCD TSC, choking de navegadores/IA, perfil de GPU, I/O e TRIM (72). |
| `extreme` | Bench / torneio | `fresh` + mitigacoes de CPU desligadas + C-states off + NDIS agressivo + watcher com pin fisico e GPU state lock (75). Risco alto, ganho real em CPU-bound. |

O perfil `auto` escolhe assim: notebook → `laptop`; desktop com tier `low` → `lowend`; resto → `gaming`.

## O que é ajustado

**Energia e CPU**
- Plano de energia próprio (`BNQQ Gaming` ou `BNQQ Balanced`) com estado de processador, boost mode, cooling policy
- Power Throttling desligado
- Core parking desligado (só desktop)
- Prioridade de foreground e MMCSS para jogos

**Entrada**
- Aceleração do mouse desligada, curvas planas (1:1)
- Keyboard Response: FilterKeys off, repeat 200/6, rate 31
- Filas HID de mouse/teclado em 20 pacotes (perfis altos; exige reboot)
- Suspensão seletiva USB desligada
- Suspensão de energia em dispositivos USB/HID desligada
- USB 3 Link Power Management desligado
- PCIe ASPM desligado

**Áudio**
- `audiodg.exe` isolado em um CPU lógico dedicado com prioridade High (tarefa elevada)
- Audio Enhancements/spatial desativados em todos os endpoints Render/Capture

**Rede**
- Throttling de rede multimídia removido
- Interrupt moderation, EEE, flow control e wake-on desligados no adaptador físico
- TCP: ECN e timestamps off, RTO 2000 ms
- QoS DSCP 46 (EF) para CS2 e Valorant (política local; exige reboot)
- DNS Cloudflare 1.1.1.1

**Sistema**
- Game DVR e Game Bar desativados
- Fast Startup desativado
- Hibernação desativada (desktop)
- Efeitos visuais reduzidos
- Telemetria, Copilot, Recall e widgets desativados
- Pagefile garantido como gerenciado
- NTFS: last access off, memory usage 2
- Kernel em RAM e dump reduzido

**Debloat**
- Apps pré-instalados removidos (lista curada)
- Tarefas de telemetria e diagnóstico desativadas por prefixo de caminho
- Recursos opcionais não usados desativados
- Delivery Optimization sem P2P
- NetBIOS sobre TCP/IP desativado

**Serviços**
- Baixo risco: telemetria, fax, wallet, geolocalização, sensores, diagnóstico, backup, mídia
- Médio risco: Spooler, Bluetooth, WSL, Docker — **só** se o hardware/recurso não existir
- Nunca: Defender, firewall, áudio, RPC, DCOM, Event Log, Task Scheduler, DNS, DHCP

**GPU**
- HAGS (build 22000+)
- MSI mode em GPU e rede
- NVIDIA: preferência por performance máxima e telemetria off
- NVIDIA state lock: `nvidia-smi -lgc` durante o jogo e `-rgc` ao fechar
- Fullscreen exclusivo forçado
- **GPU dedicada por jogo** (essencial em notebook com iGPU + dGPU)
- **VRR otimizado e swap chain moderno** para jogos em janela

**CPU (perfil `extreme`)**
- Mitigações de Spectre/Meltdown desligadas — 5–15% de CPU em troca de exposição a exploits de CPU
- C-states desligados — reduz latência de wake, sem ganho de FPS médio

**Segurança**
- Pastas de jogos (Steam, Riot, Epic, Ubisoft, Battle.net) excluídas da varredura em tempo real

**Background choking**
- Navegadores: aceleração de hardware e background mode desligados por política
- Atalhos de Chrome/Edge/Brave/Discord com flags anti-throttling (reversível)
- Copilot, Recall, Cortana e tarefas de IA/telemetria desativados
- Prioridade por processo com `CpuPriorityClass`, `IoPriority` e `PagePriority`

**Watcher e I/O**
- Plano `BNQQ Ultimate` ativado ao abrir CS2/Valorant e restaurado ao fechar
- Pin opcional nos núcleos físicos (`0x5555` em 8C/16T com SMT)
- Perfil NVIDIA/AMD por driver key
- `AdditionalCriticalWorkerThreads=8` e `AdditionalDelayedWorkerThreads=4`
- TRIM forçado em SSD NTFS

## O que ele NÃO faz

Deliberadamente fora, por não ter efeito mensurável ou por prejudicar:

- Tweaks de Nagle (`TcpAckFrequency`) — jogos usam UDP
- Desativar HPET ou forçar timer global (`useplatformclock`); `disabledynamictick` é **opt-in Pro-Tier**, com aviso de possível perda de FPS
- Desativar SysMain em SSD
- "Limpeza de registro"
- Desativar Defender por completo
- Prioridade Realtime para jogos
- Desativar SMT
- Afinidade fixa em 1–2 núcleos (o pin em todos os núcleos físicos é opt-in no `extreme` e deve ser medido)
- Packs de DNS "gamer"

## Segurança

- Exige administrador para aplicar (auto-eleva)
- Cria ponto de restauração antes de escrever
- Grava `backups/backup-<data>.json` com o valor anterior de cada chave, plano de energia, serviços e propriedades de rede
- `revert` restaura tudo
- Idempotente: rodar duas vezes não quebra
- `focus` grava `backups/focus-state.json` e só retoma o que foi suspenso

### O que o `revert` não desfaz

- **`debloat-appx`** — apps removidos não voltam. Reinstale pela Store ou `winget`.
- **`features-off`** — recursos do Windows precisam de `Enable-WindowsOptionalFeature -Online -FeatureName <nome> -All`.
- **`mitigations-off`** — o `revert` restaura o registro, mas exige reboot para o kernel voltar a aplicar as mitigações.

Tudo o mais (registro, serviços, plano de energia, rede, pagefile, tarefas) volta ao estado anterior.

## Requisitos

- Windows 10 1809+ ou Windows 11
- PowerShell 5.1+
- Administrador para `apply`, `revert`, `focus`, `unfocus`, `rebalance`, `trim`, `debloat` e `audio -AudioAction install/remove`

## Estrutura

```
bnqq.ps1              CLI
lib/Core.ps1          elevacao, log, backup, restore point
lib/Detect.ps1        deteccao de hardware, aplicabilidade, achados
lib/Tweaks.ps1        catalogo de tweaks, plano de energia, rede
lib/Services.ps1      catalogo de servicos e desativacao condicional
lib/Debloat.ps1       AppX, tarefas, recursos, kernel, NVIDIA, privacidade
lib/Tuning.ps1        input, fullscreen, TCP, DNS, tier, guia, bench, deteccao de jogos
lib/Modules.ps1       analise modular com score
lib/Verdict.ps1       classificacao por evidencia
lib/Boost.ps1         focus, ProBalance, trim, stress
lib/Peripherals.ps1   USB, HID, monitores
lib/Timer.ps1         NtSetTimerResolution/NtQueryTimerResolution
lib/Stability.ps1     carga C# + WHEA 18/19 para Curve Optimizer
lib/Qos.ps1           politicas DSCP 46 e status do Packet Scheduler
lib/Audio.ps1         audiodg, Audio Enhancements e tarefa de audio
lib/ProTier.ps1       rede/MMCSS, USB suspend e dynamic tick opt-in
lib/GodTier.ps1       CFG por jogo, FSO, paging, prioridade e auditoria shader
lib/Vanguard.ps1      IRQ/RSS/DXGI, layout de núcleos e status
lib/MemoryGuard.ps1   memtune, kernel em RAM, compressão e purga de standby
lib/Allowlist.ps1     HWID SHA-256 e consulta da allowlist Raw
lib/QA.ps1            auto-check de IRQ, SMT e timer
lib/InGameQA.ps1      engine falsa + carga C# + validação do watcher
lib/Ultimate.ps1      Super Pack: IA, servicos, MMCSS, heap e VBS
lib/Acpi.ps1          HPET/TSC e estado ACPI
lib/Msi.ps1           MSI/PCIe, prioridade e máscaras de IRQ
lib/Tui.ps1           banner, menu, deep scan com anomalias
lib/Watcher.ps1       plano Ultimate, afinidade fisica, timer, GPU lock, tarefa de logon
lib/Gpu.ps1           perfil NVIDIA/AMD por driver key
lib/Storage.ps1       I/O worker threads e TRIM
bnqq-watch.ps1        processo do watcher (logon)
bnqq-audio.ps1        processo de isolamento do audiodg (logon)
build.ps1             empacota a TUI em dist\BNQQ_Optimizer.exe
config/profiles.json  perfis
docs/what-it-does.md  efeito e risco de cada tweak
docs/GUIA_PRO.md      guia do menu para pro-players
docs/RELATORIO.md     relatório técnico completo
```

## Aviso

Desativar HVCI reduz a proteção contra exploits de kernel. É uma troca consciente por desempenho. Use `desktop` ou `laptop` se preferir manter a proteção.

Testado em Windows 11. Em Windows 10, tweaks que exigem build 22000+ são ignorados automaticamente.
