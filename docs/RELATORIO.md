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
| `god` | God-Tier: CFG por jogo, paging, prioridade e auditoria shader |
| `vanguard` | Vanguard: IRQ, RSS, DXGI, SMT e standby |
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
lib/GodTier.ps1
lib/Vanguard.ps1
lib/MemoryGuard.ps1
lib/License.ps1
lib/QA.ps1
lib/InGameQA.ps1
lib/Ultimate.ps1
bnqq-watch.ps1
bnqq-audio.ps1
build.ps1
docs/what-it-does.md
docs/GUIA_PRO.md    guia do menu para pro-players
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
| Build privado | 151.552 bytes |
| Build público | 132.096 bytes |
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

## 19. God-Tier — CFG, kernel e auditoria

### 19.1 CFG por jogo

`Set-ProcessMitigation -Name <exe> -Disable CFG` é aplicado somente a `cs2.exe` e `VALORANT-Win64-Shipping.exe`, sem `-System`. A reversão usa `-Enable CFG`. O cmdlet foi validado em um executável de teste; não foi aplicado aos jogos na máquina de validação para não arriscar anti-cheat. É opt-in de `god apply` e reduz a mitigação de exploits por jogo.

### 19.2 FSO e shader cache

`AppCompatFlags\Layers` já contém `~ DISABLEDXMAXIMIZEDWINDOWEDMODE` para os dois jogos; o módulo verifica e reaplica de forma idempotente.

Não existe DWORD público/suportado em `nvlddmkm` para tamanho do shader cache; o controle real é do NVIDIA App/perfil do driver. O módulo audita `DXCache`, `GLCache` e `D3DSCache` (5760,1 MB nesta máquina) e não injeta valor inventado. O comando `cache` limpa os caches.

### 19.3 Paging e prioridade

| Item | Antes | God-Tier |
|---|---|---|
| `DisablePagingExecutive` | 1 | 1 |
| `Win32PrioritySeparation` | 26 (`0x1A`) | **38 (`0x26`)** |
| FSO CS2/Valorant | presente | mantido |

`god remove` volta a prioridade para 26 e reabilita CFG.

### 19.4 Auditoria

Verificados: paging, FSO, network throttling/responsiveness, USB selective suspend, MSI/IRQ, NDIS/RSS, TCP ECN/timestamps, ETW autologgers e timer 0,5 ms. Não adicionados: Nagle/TcpAckFrequency (UDP), HPET forçado, timer global, DWORD NVIDIA inventado, dynamic tick em perfis padrão.

### 19.5 TUI e build

- Banner **`BNQQ OPTIMIZER v4.0 God-Tier`**.
- Deep Scan com painel `GOD-TIER / KERNEL`.
- TUI pública `[12]`; privada `[15]`.
- Build `4.0.0`, release `v4.0-godtier`.

### 19.6 Changelog 4.0 God-Tier

| Versão | Entrega |
|---|---|
| 4.0 | CFG por jogo opt-in, FSO verificado, paging/prioridade 0x26, auditoria de shader cache, Deep Scan God-Tier, TUI v4.0, build e release `v4.0-godtier` |

---

## 20. Vanguard — IRQ, SMT e standby

### 20.1 IRQ e layout

Para 8+ threads: GPU CPU 4 (`0x10`), áudio CPU 5, rede CPU 6 (`0x40`). O `vanguard apply` grava `DevicePriority=3` na GPU, `2` na rede, `DevicePolicy=4` e `AssignmentSetOverride` binário. A GPU/rede foram aplicadas e confirmaram CPU 4/6.

Em 8C/16T o jogo usa todos os núcleos físicos; os CPUs 4/6 também pertencem ao mask do jogo. Isolamento absoluto exigiria reservar núcleos e reduzir o jogo, o que não foi feito.

### 20.2 Background SMT

O watcher pina Discord/Chrome/Edge/Spotify/Brave/Firefox no mask ímpar (`0xAAAA`) durante o jogo e restaura ao fechar. Teste: Chrome `0xAAAA`, jogo `0x5555`, retorno `0xFFFF`; 24 processos pinados.

### 20.3 Standby purger

`NtSetSystemInformation` classe 80, comando 4, com `SeProfileSingleProcessPrivilege` habilitado via C#. O teste final retornou `0x00000000`; a primeira tentativa falhou com `0xC0000061` e foi corrigida. O watcher purga abaixo de 4 GB livres, no máximo a cada 60 s e somente com jogo ativo. Não foi disparado na validação (~21 GB livres).

### 20.4 Itens não suportados

- `Max Pre-rendered frames`, `Silk Smoothness` e `Threaded Optimization`: perfil do driver/NVIDIA App, sem chave pública em `nvlddmkm`.
- Timer coalescing: sem registro/powercfg suportado; timer 0,5 ms e dynamic tick opt-in são os controles reais.
- DXGI flip global: não existe override global; `SwapEffectUpgradeEnable=1` e FSO por jogo já ativos.
- RSS pinning: Ethernet não expôs RSS neste driver.

Nenhuma chave fictícia foi criada.

### 20.5 TUI, build e guia

Banner **`BNQQ OPTIMIZER v1.0.0`**; Deep Scan com painel Vanguard; TUI pública `[13]`, privada `[16]`; build `1.0.0`; release `v1.0.0`; `docs/GUIA_PRO.md`.

### 20.6 Changelog 5.0 Vanguard

| Versão | Entrega |
|---|---|
| 1.0.0 | IRQ GPU/rede, background SMT, DXGI/FSO, standby nativo, Vanguard status, TUI v5.0 e guia do pro-player; auditoria de itens não suportados |

---

## 21. Premium Licensing & QA

### 21.1 Licenciamento HWID

`lib/License.ps1` calcula SHA-256 de `UUID + ProcessorId` e exige `license.key` com assinatura RSA-2048/SHA-256. O cliente tem apenas a chave pública; `keygen.ps1` é privado e não entra no build público. Sem licença, a TUI mostra o HWID e encerra.

### 21.2 QA AMD/NVIDIA

AMD já recebe `EnableUlps=0` e Anti-Lag. O atalho do Discord recebe `--disable-gpu`; navegadores mantêm HW accel off. Discord, Slack, Teams, WhatsApp, Zoom, Telegram e Steam webhelper recebem prioridade baixa. Nenhuma chave NVIDIA inventada foi adicionada.

### 21.3 Rede e energia Premium

Checksum offload IP/TCP/UDP v4/v6 e LSO IPv4/IPv6 desligados; idle demote/promote 100 e `IDLEDISABLE=1`. Validação: checksum `Disabled` nas cinco categorias, LSO `False`, thresholds `0x64`, idle disable `0x1`.

### 21.4 QA do ambiente

`lib/QA.ps1` verifica policy de IRQ, mask SMT `0xAAAA`, watcher e timer; em idle informa que o watcher aplica 0,5 ms quando o jogo abre. O `[1] Deep Scan` mostra `QA / AMBIENTE`.

### 21.5 Build e release

Banner **`BNQQ OPTIMIZER v1.0.0`**; build `1.0.0`; release `v1.0.0`; `license.key` no payload local; `keygen.ps1` fora do build.

### 21.6 Changelog 1.0.0

| Versão | Entrega |
|---|---|
| 1.0.0 | Licença HWID RSA-SHA256, keygen privado, AMD/Discord/communication tuning, checksum/LSO off, idle power thresholds, QA de IRQ/SMT/timer, build v1.0.0 |

---

## 22. Ultimate — Super Pack e QA in-game

### 22.1 Faxina

`lib/Ultimate.ps1` aplica Copilot/Recall, Fax/Xbox/Spooler condicional, UWP agressivo (Cortana, BingNews, ZuneVideo, Solitaire, TikTok), perfil MMCSS `BNQQ_Esports`, SharedSection opt-in, VBS/DMA opt-in e lista de serviços. `wuauserv` é opt-in; estados anteriores em `backups/ultimate-services-<data>.json`.

O Spooler foi mantido por haver impressora; os serviços Xbox já estavam desativados.

### 22.2 Kernel

- `fltmc unload WdFilter` **não executado**; proteção em tempo real protegida e não deve ser descarregada.
- MMCSS `BNQQ_Esports`: `Scheduling Category=High`, `SFIO Priority=High` (REG_SZ).
- SharedSection e VBS/DMA são opt-in; não foram alterados no pacote básico.
- Nenhuma chave NVIDIA/coalescing fictícia.

### 22.3 QA in-game

`lib/InGameQA.ps1` compila `load.exe` C# e inicia um `cs2.exe` controlado. O watcher validou timer 0,5 ms, jogo `0x5555`, background `0xAAAA`, detecção e clock. Teste de 20 s: 4369→4355 MHz, queda 0,3%, veredito **ESTAVEL**; temperatura indisponível.

### 22.4 TUI, build e guia

Banner **`BNQQ OPTIMIZER v1.1.0`**; TUI privada `[17]/[18]`, pública `[14]/[15]`; build `1.1.0`; release `v1.1.0`; `docs/GUIA_PRO.md` atualizado.

### 22.5 Changelog 1.1.0

| Versão | Entrega |
|---|---|
| 1.1.0 | Super Pack pós-formatação, IA/Recall, serviços/AppX, MMCSS, heap/VBS opt-in, QA in-game C# e build v1.1.0 |

---

## 23. ACPI/HPET e MSI/PCIe

### 23.1 Versionamento

Padrão limpo **v1.1.0** em banner, `build.ps1`, `config/profiles.json` e guia.

### 23.2 HPET/TSC

`lib/Acpi.ps1` audita `useplatformclock`, `tscsyncpolicy` e `disabledynamictick` e aplica `useplatformclock=No` + `tscsyncpolicy=Enhanced`. A tabela ACPI do firmware não é editada; patch de tabela é inseguro. HPET físico permanece; o Windows usa TSC. Dynamic tick continua opt-in.

### 23.3 MSI/PCIe

`lib/Msi.ps1` varre a árvore PCI, localiza GPU/rede, garante MSI=1, prioridade 3/2, `DevicePolicy=4` e máscara `0x10` GPU / `0x40` rede. Status confirmou GPU/rede com policy 4.

### 23.4 Watcher e QA

O watcher reaplica a afinidade do background a cada ciclo de 2 s. O QA espera jogo/background antes da carga C# para nao afogar o watcher.

### 23.5 TUI e build

TUI pública `[16]/[17]`, privada `[19]/[20]`; build `1.1.0`; tag `v1.1.0`.

### 23.6 Changelog 1.1.0

| Versão | Entrega |
|---|---|
| 1.1.0 | Versionamento limpo, auditoria/apply ACPI TSC, MSI/PCIe scan e afinidade GPU/rede |

---

## 24. Licença

MIT. Uso livre, sem garantia. Tweaks de risco alto são opt-in e documentados.

---

## 25. v1.2.0 — Compensação VBS/HVCI e Motor Virtual

### 25.1 Regra de segurança

VBS e HVCI permanecem **ligados**. O modo não tenta enganar Vanguard/FACEIT/GC; não há hook, patch de driver, bootloader ou falsificação de `Win32_DeviceGuard`. A compensação trabalha em cima do custo real de virtualização.

### 25.2 Módulos entregues

| # | Módulo | Implementação |
|---|---|---|
| 1 | Versionamento | `v1.2.0` em banner, build, config, README, guia e relatório |
| 2 | Input/Periféricos | mouse accel off, `MouseHoverTime=0`, filas HID 20, USB sem suspensão, MSI/prioridade em controladoras PCI USB |
| 3 | Background | `DiagTrack`, `dmwappushservice`, `WECsvc`, `SysMain`, `WSearch`; standby purge |
| 4 | Thread isolation | watcher com jogo `0x5555`, background `0xAAAA`, revalidação de 2 s |
| 5 | Virtual QA | `lib/VirtualInGameQA.cs`: 128 ticks/s, física, memória, rede loopback e afinidade |
| 6 | Build | binários privado e público com launcher C# e payload versionado |
| 7 | MSI/PCIe | GPU e Realtek com MSI, prioridade e máscaras; USB em CPU dedicado |
| 8 | ACPI/TSC | `useplatformclock=No`, `tscsyncpolicy=Enhanced`; tabela ACPI não é editada |
| 9 | Energia | core parking off, min/max 100%, idle disable, C-states solicitados |
| 10 | TCP | `TcpAckFrequency=1`, `TCPNoDelay=1` por interface ativa |
| 11 | GPU/cache | HAGS=2; cache de shader auditado, sem tamanho ilimitado falso |
| 12 | Relatório | este documento + limitações e ideias de evolução |

### 25.3 Perfis

Os perfis padrão deixaram de incluir `hvci-off`, `hypervisor-off` e `credential-guard-off`. Foi criado o perfil `valorant`, que mantém a virtualização e aplica apenas tweaks compatíveis.

### 25.4 QA virtual

Sem jogo real. O motor C# foi executado por 30 s:

```text
Ticks            3841 (128.0 Hz)
Jitter           avg 0.0 us · max 0.1 us
Fisica / memoria 3308505000 ops / 695292000 ops
Rede             3980 pacotes loopback
Timer            0,500 ms  [0.5 ms OK]
Afinidade jogo   0x5555  [0x5555 OK]
Afinidade SMT    0xAAAA  [0xAAAA OK]
Motor afinidade  0x5555  [OK]
Watcher detectou sim
Veredito         ESTAVEL
```

### 25.5 Comandos

```powershell
.\bnqq.ps1 compensate
.\bnqq.ps1 compensate -CompensateAction apply
.\bnqq.ps1 virtualqa -VirtualSeconds 30
.\bnqq.ps1 apply -Profile valorant
```

TUI privada `[21]/[22]`; pública `[18]/[19]`; build `1.2.0`; tag `v1.2.0`.

### 25.6 Limitações

- VBS/HVCI não são desligados; a compensação não remove todo o custo do hypervisor.
- `WSearch`/`SysMain` desativados pioram indexação e cache de arquivos.
- `TcpAckFrequency=1` aumenta ACKs; não é ideal em todo link.
- C-states efetivos dependem do firmware AMD/B550M.
- Cache de shader “ilimitado” não tem registro suportado; o driver controla.
- O QA virtual valida estabilidade sintética, não substitui um jogo real.

---

## 26. v1.3.0 — Runtime Latency, ETW e HID

### 26.1 Escopo

Fase de runtime e validação. VBS/HVCI permanecem ligados; não há hook, patch de driver, bypass de Vanguard ou falsificação de Secure Boot/TPM.

### 26.2 Módulos

| # | Módulo | Implementação |
|---|---|---|
| 1 | HID/USB runtime | filas `mouclass`/`kbdclass` em 20 pacotes, aceleração off, USB sem suspensão, MSI/prioridade e afinidade das controladoras |
| 2 | Watcher foco/QoS | `GetForegroundWindow` no watcher; QoS DSCP 46 no `ActiveStore`, padding de working set e purge de standby no foco do jogo |
| 3 | ETW/PDH | `lib/EtwMonitor.ps1`: DPC, ISR, interrupções, CPU/working set do DWM e JSON em `reports` |
| 4 | Preflight | `lib/Preflight.ps1`: Secure Boot, TPM, VBS e HVCI; bloqueia o perfil `valorant` sem conformidade |
| 5 | Virtual QA | motor C# 128 ticks/s com física, memória e loopback |
| 6 | Build/relatório | binários privado/público, documentação e tag |

### 26.3 HID e runtime

A fila de `mouclass.sys`/`kbdclass.sys` foi mantida em **20 pacotes**. Esse é o piso seguro adotado para mouse de 8 kHz; abaixo disso o risco de perda de eventos cresce. Como são drivers de boot, o novo valor de fila só entra no próximo boot. As controladoras USB AMD apareceram com MSI=1, prioridade 3, policy 4 e máscara `0x8000` (CPU 15). Isso não muda o polling do mouse; polling é hardware/firmware.

O teste direto de `Set-BnqqRuntimeLatency` confirmou:

```text
QoS runtime: DSCP 46
Working set: min 210 MB / max 466 MB
```

### 26.4 Preflight elevado

```text
Secure Boot  ativo
TPM          presente e pronto
VBS runtime  rodando
HVCI         rodando
Vanguard     detectado
Conformidade  PRONTA
```

### 26.5 Virtual QA — 30 s

```text
Ticks            3841 (128.0 Hz)
Jitter           avg 0.0 us · max 0.1 us
Fisica / memoria 3265487500 ops / 654132000 ops
Rede             2927 pacotes loopback
Timer            0,500 ms  [0.5 ms OK]
Afinidade jogo   0x5555  [0x5555 OK]
Afinidade SMT    0xAAAA  [0xAAAA OK]
Motor afinidade  0x5555  [OK]
Watcher detectou sim
Veredito         ESTAVEL
```

### 26.6 TUI e comandos

```powershell
.\bnqq.ps1 hid
.\bnqq.ps1 hid -HidAction apply
.\bnqq.ps1 etw -EtwSeconds 15
.\bnqq.ps1 preflight
.\bnqq.ps1 virtualqa -VirtualSeconds 30
```

TUI privada `[23] HID`, `[24] ETW`, `[25] Preflight`; pública `[20]/[21]/[22]`.

### 26.7 Limitações

- Working set padding não garante páginas permanentemente na RAM; o Windows pode trimar sob pressão.
- QoS DSCP depende do caminho de rede respeitar EF e não reduz ping físico.
- O monitor ETW/PDH é leve e não substitui WPR/WPA para análise de DPC/ISR.
- O preflight exige UAC para Secure Boot/TPM.
- O teste virtual não substitui partida real; não houve teste in-game manual nesta fase.

---

## 27. v1.3.1 — Deep Freeze, Large Pages e P-State

### 27.1 Módulos

| # | Módulo | Implementação |
|---|---|---|
| 1 | Versionamento | `v1.3.1` em banner, build, config, guia e README |
| 2 | Deep Freeze | suspensão/resumo via `NtSuspendProcess`/`NtResumeProcess` no foco do jogo |
| 3 | Large Pages | concessão de `SeLockMemoryPrivilege` via política local |
| 4 | GPU P-State | leitura de P-State e lock de clock máximo por `nvidia-smi` |
| 5 | Perfis + E2E | working set 192 MB CS2 / 256 MB Valorant; log de latência E2E |
| 6 | NDIS/ETW | auditoria DSCP/firewall e WPR opcional |
| 7 | QA/build | motor C# e binários finais |

### 27.2 Deep Freeze

Arquivo: `lib/DeepFreeze.ps1`

- Suspende Steam WebHelper, Discord, navegadores, updaters, OneDrive/Dropbox e launchers.
- Exclui `explorer`, Riot Client, Vanguard, áudio, DWM e processos de segurança.
- Retoma no Alt+Tab e ao fechar o jogo.
- Teste nativo em processo PowerShell: `SuspendStatus=0`, `ResumeStatus=0`.

O watcher instala com `-DeepFreeze` e passa a usar poll de 1 s para detectar perda de foco.

### 27.3 Large Pages

`SeLockMemoryPrivilege` foi concedido para `BNQY\bruno`; a mudança exige logoff/reboot para o token refletir. O privilégio **não força** CS2/Valorant a usar `VirtualAlloc(MEM_LARGE_PAGES)`; ele apenas permite que a aplicação solicite.

### 27.4 GPU P-State

Estado real:

```text
P-State  P0
Clock    1935 MHz / memória 7000 MHz
```

O controle efetivo é `nvidia-smi -lgc max -pm 1`. Não foi baixado NVIDIA Inspector; P-State 0 não tem API pública garantida via NVAPI.

### 27.5 Rede / WPR

Auditoria: 2 políticas DSCP, 2 adaptadores com `ms_pacer`, 0 regras de firewall BNQQ. Nenhum firewall foi desativado. WPR de 5 s gerou ETL em `reports`; o stop foi lento porque o WPR consolida o trace.

### 27.6 QA virtual — 30 s

```text
Ticks            3841 (128.0 Hz)
Jitter           avg 0.0 us · max 0.0 us
Fisica / memoria 3201050000 ops / 640044000 ops
Rede             1615 pacotes loopback
Timer            0,500 ms  [0.5 ms OK]
Afinidade jogo   0x5555  [0x5555 OK]
Afinidade SMT    0xAAAA  [0xAAAA OK]
Motor afinidade  0x5555  [OK]
Watcher detectou sim
Veredito         ESTAVEL
```

### 27.7 Limitações

- Deep Freeze pausa processos; Alt+Tab pode demorar até o próximo ciclo de 1 s.
- Suspender apps pode quebrar downloads/updaters; é opt-in e exclui anti-cheat/shell.
- Large Pages depende da aplicação e do token pós-logon.
- P-State 0 é observado; o clock máximo é o controle real.
- DSCP no fio não foi validado.
- WPR é pesado e pode afetar o próprio resultado.
- Não houve teste in-game real nesta fase.
