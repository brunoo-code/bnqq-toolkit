# BNQQ Toolkit — Relatório Técnico

Documento de referência do projeto público. Explica o que o toolkit é, como o motor adaptativo decide, o que cada perfil faz, o que foi medido e quais são os limites.

---

## 1. Visão

Um otimizador de latência para Windows 10/11 que **detecta o hardware e aplica apenas o que faz sentido naquele computador**.

Diferente de packs tradicionais, que aplicam a mesma lista em qualquer máquina:

- Cada tweak declara **pré-requisitos** (`Chassis`, `Gpu`, `MinRamGB`, `MinBuild`, `Storage`).
- Se a condição não bate, o tweak é **ignorado e reportado**.
- Cada tweak tem **classificação de evidência**: comprovado, provável ou neutro.
- Tudo é **reversível** por backup JSON + ponto de restauração.

O objetivo é reduzir latência e instabilidade de frame time — não "limpar o PC".

---

## 2. Público-alvo

| Tier | Hardware típico | Perfil |
|---|---|---|
| Fraco | 4–8 GB, HDD, iGPU ou GPU antiga | `lowend` |
| Notebook | qualquer notebook, com ou sem dGPU | `laptop` |
| Médio | 16 GB, SSD, GPU de entrada | `desktop` |
| Bom | 16–32 GB, SSD NVMe, GPU dedicada | `gaming` |
| Pós-formatação | qualquer máquina recém-instalada | `fresh` |
| Bench/torneio | máquina dedicada, sem dados sensíveis | `extreme` |

O motor escolhe sozinho: notebook → `laptop`; desktop com tier `low` → `lowend`; resto → `gaming`.

---

## 3. Como o motor adaptativo decide

```
1. Get-SystemInfo        le CPU, GPU, RAM, discos, chassi, build, plano, VBS
2. Get-BnqqTier          classifica em low / mid / high
3. perfil                resolve automatico ou informado
4. Get-BnqqProfile       lista de ids do perfil
5. Test-TweakApplicable  filtra por Requires
6. backup + restore point
7. apply                 executa cada tweak, registra falha individual
```

Exemplos de condição:

```powershell
@{ Id = 'core-parking-off';      Requires = @{ Chassis = 'desktop' } }
@{ Id = 'hags-on';               Requires = @{ MinBuild = 22000 } }
@{ Id = 'memory-compression-off'; Requires = @{ MinRamGB = 16 } }
@{ Id = 'sysmain-off';           Requires = @{ Storage = 'hdd' } }
@{ Id = 'nvidia-max-perf';       Requires = @{ Gpu = 'nvidia' } }
```

Consequência prática: em um notebook, core parking e hibernação nunca são tocados. Em máquina com 8 GB, a compressão de memória continua ligada. Em HDD, o SysMain é desligado — o inverso do que a maioria dos packs faz.

---

## 4. Catálogo — 80 tweaks

| Área | Itens |
|---|---|
| CPU / energia | power-plan adaptativo, power-throttling-off, core-parking-off, win32-priority, mmcss-games, cstates-off*, game-watcher, game-affinity* |
| Latência | hvci-off, credential-guard-off, hypervisor-off, ndu-off, msi-mode, timer-defaults, interrupt-affinity (desktop 8+ threads), bcd-timer |
| Memória | pagefile-managed, memory-compression-off, kernel-memory, large-system-cache |
| GPU | hags-on, nvidia-max-perf, mpo-off, gpu-preference, display-optimizations, gpu-vendor-profile, auditoria HDCP (somente leitura) |
| Display | fse-forced, fullscreen-opt |
| Input | mouse-accel-off, keyboard-response, input-queue, usb-power-off, usb3-lpm-off, usb-suspend-off, pcie-aspm-off |
| Áudio | audio-isolation (audiodg + Enhancements) |
| Rede | network-throttling, network-adapter, ndis-offloads, rss-tuning, tcp-tuning, tcp-kernel, qos-dscp, dns-fast, netbios-off, delivery-opt-off |
| Sistema | fast-startup-off, hibernate-off, visual-effects, sleep-policy, reserved-storage-off |
| Debloat | debloat-appx, tasks-off, features-off, telemetry-off, privacy-lockdown, etw-autologgers |
| Serviços | services-low, services-medium, conditional-services |
| Apps | browser-background-off, browser-choking, shortcut-flags, ai-cleanup, discord-tweaks, startup-trim, startup-launchers, steam-overlay-off, process-priority |
| Segurança | defender-exclusions, defender-cpu-limit |
| Disco | filesystem-tune, ntfs-shortnames, io-queue-depth, ssd-trim |
| CPU (extremo) | mitigations-off* |

`*` somente no perfil `extreme`.

---

## 5. Perfis

| Perfil | Tweaks | Comportamento |
|---|---|---|
| `lowend` | 54 | Prioriza liberar CPU, RAM e disco. Debloat e serviços médios. |
| `laptop` | 44 | Respeita bateria: no DC mantém downclock, ASPM e suspend USB; NDIS agressivo e afinidade de interrupção são ignorados. |
| `desktop` | 57 | Equilibrado. Sem desligar HVCI. |
| `gaming` | 71 | Agressivo: HVCI off, core parking off, memory compression off, filas HID, QoS e áudio. |
| `fresh` | 72 | Pós-formatação: inclui AppX, tarefas, recursos, kernel, MSI, filas HID, QoS e áudio. |
| `extreme` | 75 | `fresh` + mitigações de CPU off + C-states off + GPU state lock. |

---

## 6. Comandos

| Comando | Função |
|---|---|
| `scan` | Hardware, BIOS, OS e achados |
| `report` | Score por área com prioridades |
| `verdict` | Comprovado / provável / neutro + 12 mitos |
| `apply` | Aplica perfil (auto-eleva) |
| `apply -WhatIf` | Mostra sem aplicar |
| `revert` | Desfaz o último apply |
| `status` | Resumo do que está ativo |
| `focus` / `unfocus` | Suspende background, prioriza o jogo, restaura depois |
| `rebalance` | ProBalance por 60 s |
| `trim` | Libera working set de apps ociosos |
| `stress` | Boost sustentado e throttling |
| `stability` | 3–5 min de carga + WHEA 18/19 (Curve Optimizer) |
| `timer` | Timer resolution atual; watcher aplica 0,5 ms durante o jogo |
| `qos` | Políticas DSCP 46 e estado do QoS Packet Scheduler |
| `audio` | Isolamento do audiodg e Audio Enhancements; install/remove |
| `pro` | Pro-Tier: rede/MMCSS, USB selective suspend e dynamic tick opt-in |
| `build.ps1` | Gera `dist\BNQQ_Optimizer.exe` com UAC e TUI |
| `bench` | CPU, fila e disco |
| `bcd` | Estado do boot |
| `guide` | Ajustes in-game que dão FPS de verdade |
| `debloat` | Lista apps/tarefas/recursos removíveis |
| `cache` | Limpa caches de shader |

---

## 7. Diagnóstico e score

O `report` avalia 9 áreas com achados classificados por severidade:

| Área | O que mede |
|---|---|
| CPU | plano, estado do processador, core parking, SMT, boost |
| Memória | total, canais, velocidade, pagefile, standby |
| GPU | modelo, driver, HAGS, BAR, MSI, temperatura |
| Armazenamento | tipo, espaço livre, fila, TRIM, SMART (desgaste/temperatura) |
| Input | aceleração, USB, polling, HID |
| Rede | latência, jitter, perda, ECN, adaptador |
| Display | refresh, resolução, MPO, FSE |
| Sistema | VBS, Game DVR, throttling, boot, WHEA, bloat, reboot |
| Energia | plano, AC/DC, suspensão, C-states |

Cada achado tem **impacto estimado** e **ação sugerida**. O score final prioriza o que dá ganho real.

---

## 8. Evidência

| Classe | Quantidade | Critério |
|---|---|---|
| Comprovado | 28 | Efeito medido ou mecanismo direto |
| Provável | 24 | Mecanismo plausível, dependente de hardware |
| Neutro | 9 | Sem efeito em FPS |
| Mitos desmentidos | 12 | Placebo ou prejudicial |

Mitos deliberadamente fora dos perfis padrão: `useplatformclock`, `useplatformtick`, timer resolution 0.5 ms, limpar standby list, Nagle em jogo, HPET forçado, prioridade Realtime, desativar SMT, afinidade fixa, limpeza de registro, DNS "gamer". `disabledynamictick` é exceção opt-in do Pro-Tier, com aviso de possível perda de FPS.

---

## 9. Comparação com otimizadores pagos

| Recurso de pago | Equivalente aqui |
|---|---|
| ProBalance (Process Lasso) | `rebalance` |
| Performance Mode (Process Lasso) | `focus` troca o plano |
| Game Booster (Razer Cortex) | `focus` / `unfocus` |
| SmartTrim (Process Lasso) | `trim` |
| Diagnóstico de DPC (LatencyMon) | `deep` |
| Validação térmica (QuickCPU) | `stress` |
| Debloat (AtlasOS/WinUtil) | `debloat-appx`, `tasks-off`, `features-off` |
| Anti-placebo | `verdict` |

Diferença: aqui tudo é auditável, reversível e sem serviço residente.

---

## 10. Segurança e limites

- Auto-elevação só nos comandos que escrevem.
- Ponto de restauração antes de cada `apply`.
- Backup JSON com valor anterior de registro, plano, serviços e rede.
- `revert` restaura tudo.
- Idempotente.

O que o `revert` **não** desfaz:

- `debloat-appx` — apps removidos não voltam; reinstale pela Store ou `winget`.
- `features-off` — use `Enable-WindowsOptionalFeature`.
- `mitigations-off` — registro volta, mas exige reboot para o kernel reaplicar.

---

## 11. Requisitos

- Windows 10 1809+ ou Windows 11
- PowerShell 5.1+
- Administrador para `apply`, `revert`, `focus`, `unfocus`, `rebalance`, `trim`, `debloat`
- `nvidia-smi` para a seção de GPU NVIDIA (opcional)

---

## 12. Estrutura

```
bnqq.ps1
config/profiles.json
lib/Core.ps1
lib/Kernel.ps1
lib/Detect.ps1
lib/Tweaks.ps1
lib/Services.ps1
lib/Debloat.ps1
lib/Tuning.ps1
lib/Modules.ps1
lib/Verdict.ps1
lib/Boost.ps1
lib/Peripherals.ps1
lib/Timer.ps1
lib/Stability.ps1
lib/Qos.ps1
lib/Audio.ps1
lib/ProTier.ps1
bnqq-watch.ps1
bnqq-audio.ps1
build.ps1
docs/what-it-does.md
docs/RELATORIO.md   este documento
```

---

## 13. Roadmap

| Prioridade | Item |
|---|---|
| Alta | Teste em Windows 10 e em notebook com iGPU + dGPU |
| Alta | Perfil `lowend` validado em 4 GB e 8 GB |
| Média | Detecção de throttling de GPU |
| Média | Relatório exportável em HTML |
| Baixa | Suporte a AMD Anti-Lag |
| Baixa | Tradução para inglês |

---

## 14. Módulos de baixo nível (v3.0)

`lib/Kernel.ps1` adiciona a camada de barramento, interrupção e kernel dispatcher. Todos os tweaks passam pelo mesmo `Test-TweakApplicable`, gravam backup em JSON e são revertidos por `revert`.

### 14.1 MSI e prioridade de interrupção

- `Set-BnqqMsiPriority` grava `MSISupported=1` e `DevicePriority` (GPU High, NIC Normal, xHCI High) em `...\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties`.
- `MessageNumberLimit` só é gravado quando ausente, e apenas para a GPU (`1`). Nunca sobrescreve o limite definido pelo driver.
- Vale para qualquer desktop ou notebook: é uma configuração suportada pelo Windows e não altera integridade de boot.

### 14.2 Afinidade de interrupção (somente desktop, 8+ threads)

- `Set-BnqqInterruptAffinity` grava `DevicePolicy=4` e `AssignmentSetOverride` (REG_BINARY, bitmask de 8 bytes) em `...\Interrupt Management\Affinity Policy`.
- Núcleos 0-3 ficam livres; GPU, rede e USB são distribuídos nos grupos seguintes.
- **Filtros de segurança:** `Requires = @{ Chassis='desktop'; MinThreads=8 }` e uma segunda checagem em runtime (`Test-BnqqLaptop`). Em notebook ou CPU de 4 núcleos/8 threads, o tweak é ignorado.
- Objetivo: evitar que DPC/ISR de rede e GPU preemptem o thread principal. O ganho esperado é no 0.1% low, não na média.

### 14.3 NDIS por RegistryKeyword

- O motor antigo casava `DisplayName` em inglês e falhava silenciosamente em Windows localizado. Agora usa `RegistryKeyword` (`*InterruptModeration`, `*EEE`, `EnableGreenEthernet`, `*LsoV2IPv4`, ...), neutro de idioma.
- **Modo padrão (todos os perfis):** interrupt moderation, EEE, Advanced EEE, Green Ethernet, GigaLite e wake-on-LAN off.
- **Modo agressivo (`extreme`):** adiciona Flow Control e LSO v2 off. Em notebook o modo agressivo é **ignorado automaticamente** para não prejudicar bateria e throughput.
- Cada alteração grava o valor anterior em `Meta.NetAdapter` e o `revert` restaura por keyword.

### 14.4 RSS

- Ativa `*RSS` quando o driver expõe. Em desktop com 8+ threads define `BaseProcessorNumber=4` e `MaxProcessors=4`; em notebook as filas são mantidas.
- Quando o driver não expõe `*RSS` (caso do Realtek 8125 em alguns drivers), o tweak registra "não suportado" e não falha.

### 14.5 TCP kernel

- `timestamps=disabled`, `ecncapability=disabled`, `autotuninglevel=normal`.
- `congestionprovider=ctcp`, `dca` e `netdma` são tentados; se o build recusar, o log registra "não suportado" e o apply continua.
- Não mexe em Nagle, `TcpAckFrequency` ou `TCPNoDelay` — jogos usam UDP e isso é placebo.

### 14.6 NTFS e memória

- `ntfs-shortnames`: `fsutil behavior set disable8dot3 1`. Afeta apenas arquivos novos.
- `large-system-cache`: corrigido para `LargeSystemCache=0`, priorizando working set dos jogos em vez de cache de arquivos do kernel.
- `kernel-memory` já mantinha `DisablePagingExecutive=1`.
- **`IoPageLockLimit` não é implementado:** valor legado ignorado desde o Vista. Gravar seria placebo.

### 14.7 ETW

- `etw-autologgers` desliga sessões de autologger que casam `DiagTrack|DeviceCensus|CEIP|AutoLogger-Diagtrack`.
- Sessões essenciais de Event Log não são tocadas.

### 14.8 BCD

- `bcd-timer`: `useplatformclock No` (TSC) e `tscsyncpolicy Enhanced`.
- **`disabledynamictick Yes` é opt-in Pro-Tier.** É global (afeta AC e DC) e no Windows 11 pode aumentar interrupções de timer e reduzir FPS. Fica fora dos perfis padrão e exige decisão explícita; em notebook, avalie o custo de bateria.
- **Timer resolution 0.5 ms não é implementado:** desde o Windows 10 2004 é por processo; forçar exigiria injeção no jogo, o que é incompatível com Vanguard/VAC.

### 14.9 Anti-cheat

Nenhum tweak ativa `testsigning`, desativa DEP/NX, quebra Secure Boot ou invalida assinatura. Não há hook, driver não assinado ou injeção em processo de jogo.

---

## 15. Fase 2 — TUI, watcher ativo e choking de background

A Fase 2 transforma o toolkit em um software interativo: menu, varredura com progresso, detecção de jogos em múltiplas fontes, watcher de plano de energia, perfil de GPU por vendor e tuning de I/O.

### 15.1 Detecção de jogos

A busca antiga usava `-Depth 4` a partir de `C:\Riot Games`. O executável do VALORANT fica 5 níveis abaixo:

```
C:\Riot Games\VALORANT\live\ShooterGame\Binaries\Win64\VALORANT-Win64-Shipping.exe
```

`Get-BnqqInstalledGameRoots` agora combina quatro fontes:

1. **Registro Uninstall** (HKLM 64-bit, WOW6432Node e HKCU), com `InstallLocation` e `DisplayIcon`.
2. **`C:\ProgramData\Riot Games\RiotClientInstalls.json`** — o Riot Client não registra o VALORANT no Uninstall, mas expõe `associated_client`, `rc_default` e `rc_live`.
3. **Processos em execução** (`RiotClientServices`, `VALORANT`, `cs2`, `League`).
4. **Caminhos conhecidos** em C:, D: e E:.

A varredura final percorre cada raiz uma vez com `-Filter '*.exe' -Recurse -Depth 8` e deduplica por nome em hash set. Custo medido: **0,9 s** para CS2 + VALORANT + League of Legends.

Isso corrige `fullscreen-opt`, `gpu-preference`, `defender-exclusions` e o watcher. As regras de `CpuPriorityClass` e MMCSS já eram por nome de executável, então não dependiam do caminho.

### 15.2 TUI e Deep Scan

`bnqq.ps1` sem parâmetros abre a TUI em host interativo. O menu:

```
[1] Deep Scan          varredura real em 10 etapas com Write-Progress
[2] Aplicar perfil     lowend | laptop | desktop | gaming | fresh | extreme | auto
[3] Reverter           restore do ultimo backup
[4] Game watcher       status, instalar, instalar com pin fisico, remover
[5] Relatorio modular  score por area
[6] Veredito           proven | likely | neutral | debunked
```

O Deep Scan executa consultas reais (CIM, MSI, NDIS, SMART, serviços, tarefas, BCD) e só avança a barra depois de cada consulta. A saída mostra tier, CPU, RAM, GPU, display, interrupções, adaptadores, discos, jogos e anomalias.

Anomalias verificadas:

- **SMBIOS inconsistente** — placa Intel com CPU AMD, ou modelo que não corresponde ao vendor.
- **Resizable BAR desativado** — BAR1 ≤ 1024 MB.
- **VBS/HVCI ativo**, **pagefile ausente**, **RAM abaixo de 2933 MT/s**, **reinício pendente**.
- **Executável de jogo registrado em pasta inexistente**.

### 15.3 Choking de background

| Item | Implementação | Efeito |
|---|---|---|
| Chrome/Edge/Brave | Políticas `HardwareAccelerationModeEnabled=0`, `BackgroundModeEnabled=0`, `StartupBoostEnabled=0` | Libera contexto gráfico e VRAM; impede renderer residente |
| Atalhos | Flags `--disable-background-timer-throttling --disable-renderer-backgrounding --disable-software-rasterizer` em `.lnk` | Timers de background não acordam a CPU |
| Discord | `enableHardwareAcceleration=false`, overlay e autostart off | Overlay não injeta hook |
| Copilot/Recall | `TurnOffWindowsCopilot=1`, `DisableAIDataAnalysis=1`, `AllowRecallEnablement=0` | Remove modelos e indexação de IA |
| Cortana | Remoção do AppX `Microsoft.549981C3F5F10` | Elimina processo residente |
| Tarefas | `WindowsAI`, `Application Experience`, `CEIP` desativadas | Remove varreduras periódicas |
| Defender | Exclusão das pastas reais dos jogos via `Get-BnqqGameExes` | Varredura em tempo real não inspeciona assets |

**Decisão de engenharia:** o `Preferences` JSON do Chromium não é reescrito. O arquivo tem vários MB e o round-trip `ConvertFrom-Json | ConvertTo-Json` pode alterar tipos numéricos e corromper preferências. A política de registro é o mecanismo suportado, idempotente e reversível; os atalhos cobrem o resto.

### 15.4 Dynamic Power & Process Affinity

**Watcher (`bnqq-watch.ps1` + `lib/Watcher.ps1`):** polling de 2 s, tarefa de logon `BNQQ Game Watcher` com `RunLevel Highest`. Ao detectar `cs2.exe` ou `VALORANT-Win64-Shipping.exe`:

1. Salva o GUID do plano ativo.
2. Cria/reutiliza **BNQQ Ultimate** (duplicado do Ultimate Performance; fallback para High Performance).
3. Aplica `PROCTHROTTLEMIN=100`, `PROCTHROTTLEMAX=100`, `CPMINCORES=100`, `CPMAXCORES=100`, `IDLEDISABLE=1`, `PERFBOOSTMODE=2`, `PERFBOOSTPOL=100`, `STANDBYIDLE=0`, `HIBERNATEIDLE=0`, `DISKIDLE=0`, `ASPM=0`.
4. Com `-PinPhysical`, aplica `ProcessorAffinity` nos núcleos físicos.

Ao fechar o jogo, restaura o plano anterior. Em notebook, `-RespectBattery` impede a troca na bateria.

**Máscara física:** em 8C/16T com SMT adjacente, `0x5555` (CPUs 0,2,4,6,8,10,12,14). Teste contínuo confirmou troca para BNQQ Ultimate, afinidade `0x5555` e retorno ao plano anterior.

**Correção técnica:** `Image File Execution Options\PerfOptions` **não tem valor de afinidade**. Aceita `CpuPriorityClass`, `IoPriority` e `PagePriority` — o projeto grava `3/3/5` para jogos e `5/1/1` para overlays. Afinidade real é runtime, via `Process.ProcessorAffinity`.

**Custo:** pinar reduz contenção de SMT, mas reduz threads efetivas. `game-affinity` é opt-in no `extreme`, restrito a desktop com 8+ threads, e o veredito pede medição de 0.1% low. Em CPU híbrida (P/E cores) a máscara par/ímpar não é confiável.

### 15.5 Perfil de GPU por vendor

**NVIDIA:** `DisableDynamicPstate=1`; `ShaderCacheSize=0xFFFFFFFF` **somente se o valor já existir**; `nvidia-smi -pm 1` quando o driver aceita (em GeForce frequentemente retorna não suportado, logado como INFO).

**AMD:** `EnableUlps=0`, `KMD_DeLagEnabled=1`, `PP_ThermalAutoThrottlingEnable=0`, `DisableDrmdmaPowerGating=1`.

**Não implementado:** Reflex global não existe como chave de registro — é NVAPI, implementado pelo jogo. Filtragem de textura AMD é configuração do Radeon Software, não valor estável de `AMDKMDAG`. O relatório registra a limitação em vez de inventar chave.

### 15.6 Armazenamento

- **I/O queue depth:** `AdditionalCriticalWorkerThreads=8` e `AdditionalDelayedWorkerThreads=4` em `Session Manager\I/O System`. Exige reboot.
- **TRIM:** `Optimize-Volume -ReTrim` em volumes NTFS fixos cujo `Get-PhysicalDisk` reporta SSD, com cronômetro por volume. Pode levar minutos em SSD cheio; é intencional e logado.

### 15.7 Anti-cheat e reversibilidade

Nada injeta código em processo de jogo, instala driver não assinado, ativa `testsigning`, desativa DEP/NX ou quebra Secure Boot. O watcher usa APIs públicas (`powercfg`, `ProcessorAffinity`). Registro volta pelo backup JSON; atalhos voltam por `Meta.Shortcuts`; o watcher é removido por `Unregister-ScheduledTask`.

**Limites do revert:** AppX removido (Cortana, debloat) não é reinstalado; recursos opcionais não são reativados; o plano BNQQ Ultimate permanece inativo no sistema.

### 15.8 Verificação na máquina de validação

| Item | Resultado |
|---|---|
| `apply -Profile extreme` | 72 aplicáveis, 0 falhas, 26 exigem reboot |
| Watcher | tarefa de logon em execução; `cs2.exe` → BNQQ Ultimate, afinidade `0x5555`, retorno ao plano anterior |
| IFEO | `CpuPriorityClass=3`, `IoPriority=3`, `PagePriority=5` para CS2 e VALORANT |
| MMCSS | GPU Priority 8, Priority 6, Clock Rate 10000, SystemResponsiveness 0 |
| Navegadores | políticas de HW accel/background/startup boost = 0 |
| IA | Copilot/Recall bloqueados, 1 tarefa de IA desativada |
| I/O | worker threads 8/4 |
| TRIM | C: 5,2 s · D: 2,7 s |
| `report` | 98/100; único achado real é ReBAR desativado (BIOS) |
| `deep` | 4467 MHz, DPC 0%, ISR 0,33%, GPU P0, PCIe Gen3 x16 |

O `report` foi corrigido para ler ECN por linha: antes, o texto agregado de `netsh` fazia `ECN.*enabled` casar com linhas posteriores e gerar falso positivo.

### 15.9 Changelog 2.1

| Versão | Entrega |
|---|---|
| 2.1 | TUI + Deep Scan com anomalias, detecção de jogos por Uninstall/Riot manifest/processo, choking de navegadores e IA, watcher BNQQ Ultimate com pin físico opcional, perfil NVIDIA/AMD, I/O worker threads, TRIM forçado |

---

## 16. Fase 4 — estabilidade, timer, HID e QoS

### 16.1 Estabilidade PBO com WHEA

`lib/Stability.ps1` compila um gerador de carga inteiro em C# (`Add-Type`) e inicia uma thread por processador lógico. O módulo registra o horário de início, consulta o log `System` por eventos `Microsoft-Windows-WHEA-Logger` IDs **18** e **19** durante a carga e espera 5 s após o fim. Eventos antigos não contam; se o log não puder ser lido, o veredito é `Indeterminado`.

- Falha: `Instabilidade detectada no Undervolt! Reduza o Curve Optimizer na BIOS (ex: de -15 para -10)`.
- Sucesso: `Sistema 100% Estável no Curve Optimizer`.
- JSON: `reports/stability-<data>.json`, com janela, threads, eventos e veredito.

```powershell
.\bnqq.ps1 stability
.\bnqq.ps1 stability -StabilityMinutes 3
.\bnqq.ps1 stability -StabilitySeconds 30 -StabilityThreads 8
```

O teste é sintético; não substitui horas de jogo e não detecta falhas que não gerem WHEA.

### 16.2 Timer resolution dinâmico

`lib/Timer.ps1` usa `NtQueryTimerResolution` e `NtSetTimerResolution` via P/Invoke em `ntdll.dll`. O watcher solicita 5000 (0,5 ms) quando detecta `cs2.exe`/`VALORANT-Win64-Shipping.exe` e libera quando nenhum jogo resta. A chamada ocorre no processo do watcher, não no jogo: sem injeção, hook ou driver. O `finally` libera a referência no encerramento. O comando `timer` mostra o valor atual; não há tweak de HPET/BCD associado.

### 16.3 HID

`keyboard-response` grava `Keyboard Response` com `Flags=122`, `AutoRepeatDelay=200`, `AutoRepeatRate=6`, `BounceTime=0` e `DelayBeforeAcceptance=0`, além de `KeyboardDelay=0` e `KeyboardSpeed=31`. `input-queue` reduz as filas `MouseDataQueueSize`/`KeyboardDataQueueSize` de 100 para **20**; é o menor valor considerado seguro, pode descartar input sob carga extrema, exige reboot e tem risco médio. Não altera driver, polling rate ou firmware.

### 16.4 QoS DSCP 46

`lib/Qos.ps1` cria políticas locais em `HKLM\SOFTWARE\Policies\Microsoft\Windows\QoS` para `cs2.exe` e `VALORANT-Win64-Shipping.exe`, UDP, DSCP **46** (EF), sem throttle. `qos` mostra as políticas e o QoS Packet Scheduler. A política é lida no boot ou após `gpupdate /force`; `Get-NetQosPolicy` pode ficar vazio até lá. DSCP só ajuda se o roteador/caminho respeitar EF; não reduz latência física.

### 16.5 MPO e HDCP

MPO já é tratado por `OverlayTestMode=5` nos perfis altos. HDCP não possui API/registro público suportado para desativação na NVIDIA; `Get-BnqqHdcpStatus` faz apenas auditoria (`sem controle HDCP suportado`) e não aplica hack não documentado que possa quebrar vídeo/DRM.

### 16.6 Verificação na máquina de validação

| Item | Resultado |
|---|---|
| `apply -Profile extreme` (Fase 4) | 74 tweaks, 0 falhas, 28 exigem reboot |
| Estabilidade | 180 s, 16 threads, 0 eventos WHEA 18/19, veredito estável |
| Timer | 15,625 ms em repouso → 0,500 ms com jogo → liberado ao fechar |
| Keyboard Response | Flags 122, repeat 200/6, bounce 0, delay 0 |
| Filas HID | mouse 20 / teclado 20 |
| QoS | duas políticas DSCP 46 gravadas; `ms_pacer` ativo em 2 adaptadores |
| HDCP | sem controle suportado; não aplicado |
| `report` | 99/100; GPU 94/100 por HDCP/ReBAR informativos, sem ação prioritária |
| Watcher | tarefa em execução, pin físico ativo, timer integrado |

### 16.7 Changelog 2.3

| Versão | Entrega |
|---|---|
| 2.3 | Estabilidade PBO com WHEA 18/19, timer 0,5 ms via watcher, Keyboard Response completo, filas HID 20, QoS DSCP 46, auditoria HDCP, comandos `stability`/`timer`/`qos` e opções 7–9 na TUI |

---

## 17. Fase 5 — áudio, GPU state lock e executável

### 17.1 Isolamento de áudio

`lib/Audio.ps1` implementa `audio-isolation`:

- `DisableSpatialOnComboEndpoints=1`;
- `PKEY_AudioEndpoint_Disable_SysFx` (`{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},7`) = 1 em endpoints Render/Capture;
- tarefa `BNQQ Audio Isolation` elevada no logon, loop de 5 s;
- `audiodg.exe` no CPU lógico **5** (máscara `0x20`) com prioridade **High**.

O watcher usa CPUs pares (`0x5555`); o áudio fica no thread ímpar. `audiodg.exe` é protegido: um shell comum não lê afinidade/prioridade, mas a tarefa elevada aplica. O `revert` remove a tarefa e devolve audiodg ao mask completo/Normal.

Validação na máquina de referência:

| Item | Resultado |
|---|---|
| Tarefa | Running |
| Afinidade | `0x20` |
| Prioridade | High |
| Endpoints com SysFx desativado | 27 |
| Spatial global | 1 |

### 17.2 NVIDIA State Lock

`Get-BnqqGpuMaxClock`, `Set-BnqqGpuClockLock` e `Clear-BnqqGpuClockLock` usam `nvidia-smi`. O watcher executa `-lgc <max>,<max>` ao detectar o jogo e `-rgc` ao fechar; o `finally` também libera no encerramento. Na RTX 2060, o máximo reportado foi `2145 MHz`; `-lgc 2145,2145` retornou `GPU clocks set` e `-rgc` retornou `All done`.

O lock define a faixa; o clock instantâneo pode permanecer abaixo em idle/power cap. Não é benchmark de FPS.

### 17.3 Executável único

`build.ps1` compila um launcher C# com `csc.exe` e embute ZIP com `bnqq.ps1`, `bnqq-watch.ps1`, `bnqq-audio.ps1`, `lib/` e `config/`. O launcher usa manifesto `requireAdministrator`, subsystem console, extração versionada em `%LOCALAPPDATA%\BNQQ_Optimizer\<versão>` e inicia a TUI via `powershell.exe`. Em erro, aguarda Enter.

Validação:

| Item | Resultado |
|---|---|
| Build privado | 108.032 bytes |
| Build público | 88.576 bytes |
| Manifesto | requireAdministrator presente |
| `--check` | payload extraído com scripts/lib/config |
| Assinatura | ausente; SmartScreen pode avisar |

`dist/` está no `.gitignore`; o código e o `build.ps1` são a fonte reproduzível.

### 17.4 Verificação

| Item | Resultado |
|---|---|
| `apply -Profile extreme` no privado | 78 tweaks, 0 falhas, 28 reboot |
| Público `apply -WhatIf -Profile extreme` | 75 aplicáveis, 0 ignorados |
| TUI | opção 13 no privado, 10 no público |
| Áudio | tarefa Running; `0x20`/High; 27 endpoints |
| GPU | `-lgc`/`-rgc` aceitos pelo driver |
| EXE | builds privado e público gerados; manifesto e payload conferidos |

### 17.5 Changelog 3.0

| Versão | Entrega |
|---|---|
| 3.0 | Áudio isolado persistente, Audio Enhancements off, NVIDIA state lock, build.ps1 com EXE auto-elevado e TUI, comando `audio`, opções de TUI e release `v3.0-final` |

---

## 18. Pro-Tier — rede e energia

### 18.1 Ajustes

`lib/ProTier.ps1` implementa quatro ajustes opt-in:

| Item | Implementação |
|---|---|
| Network Throttling | `NetworkThrottlingIndex=0xFFFFFFFF` |
| MMCSS | `SystemResponsiveness=0` |
| USB selective suspend | `Set-BnqqPowerValue` no plano ativo, AC/DC = 0 |
| Kernel dynamic ticks | `bcdedit /set disabledynamictick Yes` |

O `network-throttling` público foi corrigido de `SystemResponsiveness=10` para `0`. O USB selective suspend já existia como `usb-suspend-off`; o Pro-Tier verifica AC/DC no plano ativo.

### 18.2 Comandos e TUI

```powershell
.\bnqq.ps1 pro
.\bnqq.ps1 pro -ProTierAction apply
.\bnqq.ps1 pro -ProTierAction remove
```

- `[1] Deep Scan` mostra `PRO-TIER / REDE E ENERGIA` e pergunta se deseja aplicar quando houver pendência.
- TUI pública: opção `[11]`; privada: `[14]`.
- Banner: **`v3.1 Pro`**.
- `pro apply` exige UAC e reboot; `pro remove` restaura rede/USB padrão e libera dynamic tick.

### 18.3 Dynamic tick: opt-in

`disabledynamictick Yes` não entra nos perfis padrão. No Windows 11, o dynamic tick reduz interrupções de timer em idle e este projeto já mediu perda de FPS; o Pro-Tier é opt-in explícito, com aviso. Em notebook, afeta AC/DC e pode afetar bateria.

### 18.4 Validação

| Item | Estado |
|---|---|
| `NetworkThrottlingIndex` | 4294967295 — OK |
| `SystemResponsiveness` | 0 — OK |
| USB selective suspend AC/DC | 0/0 — OK |
| `disabledynamictick` | não definido — pendente |
| `pro status` | 3 OK, 1 pendente |
| `bcdedit /enum {current}` elevado | leitura OK |
| Teste apply/remove | tick `Yes` aplicado e removido sem reboot; estado final sem dynamic tick |

O dynamic tick não foi deixado ativo na máquina de validação; está disponível via `pro apply` com decisão explícita.

### 18.5 Changelog 3.1 Pro

| Versão | Entrega |
|---|---|
| 3.1 | Pro-Tier com NetworkThrottlingIndex, SystemResponsiveness 0, USB selective suspend e dynamic tick opt-in; verificação no Deep Scan; opções 14/11; banner v3.1 Pro; build atualizado; release `v3.1-pro` |

---

## 19. Licença

MIT. Uso livre, sem garantia. Tweaks de risco alto são opt-in e documentados.
