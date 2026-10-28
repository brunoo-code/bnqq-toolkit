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

## 4. Catálogo — 69 tweaks

| Área | Itens |
|---|---|
| CPU / energia | power-plan adaptativo, power-throttling-off, core-parking-off, win32-priority, mmcss-games, cstates-off* |
| Latência | hvci-off, credential-guard-off, hypervisor-off, ndu-off, msi-mode, timer-defaults, interrupt-affinity (desktop 8+ threads), bcd-timer |
| Memória | pagefile-managed, memory-compression-off, kernel-memory, large-system-cache |
| GPU | hags-on, nvidia-max-perf, mpo-off, gpu-preference, display-optimizations |
| Display | fse-forced, fullscreen-opt |
| Input | mouse-accel-off, keyboard-response, usb-power-off, usb3-lpm-off, usb-suspend-off, pcie-aspm-off |
| Rede | network-throttling, network-adapter, ndis-offloads, rss-tuning, tcp-tuning, tcp-kernel, dns-fast, netbios-off, delivery-opt-off |
| Sistema | fast-startup-off, hibernate-off, visual-effects, sleep-policy, reserved-storage-off |
| Debloat | debloat-appx, tasks-off, features-off, telemetry-off, privacy-lockdown, etw-autologgers |
| Serviços | services-low, services-medium, conditional-services |
| Apps | browser-background-off, discord-tweaks, startup-trim, startup-launchers, steam-overlay-off, process-priority |
| Segurança | defender-exclusions, defender-cpu-limit |
| Disco | filesystem-tune, ntfs-shortnames |
| CPU (extremo) | mitigations-off* |

`*` somente no perfil `extreme`.

---

## 5. Perfis

| Perfil | Tweaks | Comportamento |
|---|---|---|
| `lowend` | 52 | Prioriza liberar CPU, RAM e disco. Debloat e serviços médios. |
| `laptop` | 43 | Respeita bateria: no DC mantém downclock, ASPM e suspend USB; NDIS agressivo e afinidade de interrupção são ignorados. |
| `desktop` | 54 | Equilibrado. Sem desligar HVCI. |
| `gaming` | 62 | Agressivo: HVCI off, core parking off, memory compression off. |
| `fresh` | 63 | Pós-formatação: inclui AppX, tarefas, recursos, kernel, MSI. |
| `extreme` | 65 | `fresh` + mitigações de CPU off + C-states off. |

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

Mitos deliberadamente fora: `useplatformclock`, `disabledynamictick`, `useplatformtick`, timer resolution 0.5 ms, limpar standby list, Nagle em jogo, HPET forçado, prioridade Realtime, desativar SMT, afinidade fixa, limpeza de registro, DNS "gamer".

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
- **`disabledynamictick Yes` não existe no catálogo público.** É global (afeta AC e DC) e no Windows 11 aumenta interrupções de timer. Ficaria em conflito direto com o requisito de não degradar notebooks em bateria.
- **Timer resolution 0.5 ms não é implementado:** desde o Windows 10 2004 é por processo; forçar exigiria injeção no jogo, o que é incompatível com Vanguard/VAC.

### 14.9 Anti-cheat

Nenhum tweak ativa `testsigning`, desativa DEP/NX, quebra Secure Boot ou invalida assinatura. Não há hook, driver não assinado ou injeção em processo de jogo.

---

## 15. Licença

MIT. Uso livre, sem garantia. Tweaks de risco alto são opt-in e documentados.
