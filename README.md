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

## Uso

```powershell
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

# Ver o que seria feito
.\bnqq.ps1 apply -WhatIf

# Desfazer
.\bnqq.ps1 revert
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
.\bnqq.ps1 bench      # CPU, fila e disco
.\bnqq.ps1 bcd        # estado do boot
.\bnqq.ps1 guide      # ajustes in-game que dao FPS de verdade
```

## Perfis

| Perfil | Alvo | Comportamento |
|---|---|---|
| `lowend` | PC fraco, 4–8 GB, HDD | Prioriza liberar CPU, RAM e disco. Debloat e serviços médios incluídos. |
| `laptop` | Notebook | Respeita bateria: no DC mantém downclock e economia. Não mexe em core parking nem HVCI. NDIS agressivo e afinidade de interrupção são ignorados automaticamente. |
| `desktop` | Desktop | Equilibrado. Sem desligar HVCI. Inclui afinidade de interrupção se houver 8+ threads. |
| `gaming` | Desktop competitivo | Agressivo. HVCI off, core parking off, memory compression off, MSI + prioridade de interrupção. |
| `fresh` | Pós-formatação | Tudo do `gaming` + remoção do hypervisor no boot + RSS, TCP kernel, NTFS 8.3, ETW autologgers, BCD TSC. |
| `extreme` | Bench / torneio | `fresh` + mitigacoes de CPU desligadas + C-states off + NDIS agressivo. Risco alto, ganho real em CPU-bound. |

O perfil `auto` escolhe assim: notebook → `laptop`; desktop com tier `low` → `lowend`; resto → `gaming`.

## O que é ajustado

**Energia e CPU**
- Plano de energia próprio (`BNQQ Gaming` ou `BNQQ Balanced`) com estado de processador, boost mode, cooling policy
- Power Throttling desligado
- Core parking desligado (só desktop)
- Prioridade de foreground e MMCSS para jogos

**Entrada**
- Aceleração do mouse desligada, curvas planas (1:1)
- Suspensão seletiva USB desligada
- Suspensão de energia em dispositivos USB/HID desligada
- USB 3 Link Power Management desligado
- PCIe ASPM desligado

**Rede**
- Throttling de rede multimídia removido
- Interrupt moderation, EEE, flow control e wake-on desligados no adaptador físico
- TCP: ECN e timestamps off, RTO 2000 ms
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
- Fullscreen exclusivo forçado
- **GPU dedicada por jogo** (essencial em notebook com iGPU + dGPU)
- **VRR otimizado e swap chain moderno** para jogos em janela

**CPU (perfil `extreme`)**
- Mitigações de Spectre/Meltdown desligadas — 5–15% de CPU em troca de exposição a exploits de CPU
- C-states desligados — reduz latência de wake, sem ganho de FPS médio

**Segurança**
- Pastas de jogos (Steam, Riot, Epic, Ubisoft, Battle.net) excluídas da varredura em tempo real

## O que ele NÃO faz

Deliberadamente fora, por não ter efeito mensurável ou por prejudicar:

- Tweaks de Nagle (`TcpAckFrequency`) — jogos usam UDP
- Desativar HPET ou forçar timer global (`useplatformclock`, `disabledynamictick`)
- Desativar SysMain em SSD
- "Limpeza de registro"
- Desativar Defender por completo
- Prioridade Realtime para jogos
- Desativar SMT
- Afinidade fixa de CPU por processo
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
- Administrador para `apply`, `revert`, `focus`, `unfocus`, `rebalance`, `trim` e `debloat`

## Estrutura

```
bnqq.ps1              CLI
lib/Core.ps1          elevacao, log, backup, restore point
lib/Detect.ps1        deteccao de hardware, aplicabilidade, achados
lib/Tweaks.ps1        catalogo de tweaks, plano de energia, rede
lib/Services.ps1      catalogo de servicos e desativacao condicional
lib/Debloat.ps1       AppX, tarefas, recursos, kernel, NVIDIA, privacidade
lib/Tuning.ps1        input, fullscreen, TCP, DNS, tier, guia, bench
lib/Modules.ps1       analise modular com score
lib/Verdict.ps1       classificacao por evidencia
lib/Boost.ps1         focus, ProBalance, trim, stress
lib/Peripherals.ps1   USB, HID, monitores
config/profiles.json  perfis
docs/what-it-does.md  efeito e risco de cada tweak
docs/RELATORIO.md     relatório técnico completo
```

## Aviso

Desativar HVCI reduz a proteção contra exploits de kernel. É uma troca consciente por desempenho. Use `desktop` ou `laptop` se preferir manter a proteção.

Testado em Windows 11. Em Windows 10, tweaks que exigem build 22000+ são ignorados automaticamente.
