# BNQQ Toolkit

Otimizador de latência e estabilidade para Windows, com motor adaptativo: ele **detecta o hardware** e aplica apenas os ajustes que fazem sentido naquele computador. Funciona em desktop e notebook, AMD e Intel, NVIDIA, AMD e Intel.

Nada é aplicado às cegas. Cada tweak tem pré-requisito declarado, efeito documentado e rollback automático.

## O problema que ele resolve

Packs de otimização tradicionais aplicam a mesma lista em qualquer máquina. Em um notebook, isso significa desativar economia de energia e superaquecer. Em uma GPU que não suporta HAGS, significa habilitar algo que quebra o driver. Aqui cada tweak declara sua condição:

```powershell
@{ Id = 'core-parking-off'; Requires = @{ Chassis = 'desktop' } }
@{ Id = 'hags-on';          Requires = @{ MinBuild = 22000 } }
@{ Id = 'memory-compression-off'; Requires = @{ MinRamGB = 16 } }
@{ Id = 'hvci-off';         Requires = @{ Chassis = 'desktop' } }
```

Se a condição não bate, o tweak é ignorado e reportado como tal.

## Uso

```powershell
# Analisar
.\bnqq.ps1 scan

# Aplicar perfil automatico (detecta notebook ou desktop)
.\bnqq.ps1 apply

# Perfil especifico
.\bnqq.ps1 apply -Profile laptop
.\bnqq.ps1 apply -Profile desktop
.\bnqq.ps1 apply -Profile gaming

# Ver o que seria feito
.\bnqq.ps1 apply -WhatIf

# Desfazer
.\bnqq.ps1 revert
```

## Perfis

| Perfil | Alvo | Comportamento |
|---|---|---|
| `laptop` | Notebook | Respeita bateria: no DC mantém downclock e economia. Não mexe em core parking nem HVCI. |
| `desktop` | Desktop | Equilibrado. Sem desligar HVCI. |
| `gaming` | Desktop competitivo | Agressivo. HVCI off, core parking off, memory compression off. |

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
- PCIe ASPM desligado

**Rede**
- Throttling de rede multimídia removido
- Interrupt moderation, EEE, flow control e wake-on desligados no adaptador físico

**Sistema**
- Game DVR e Game Bar desativados
- Fast Startup desativado
- Hibernação desativada (desktop)
- Efeitos visuais reduzidos
- Telemetria desativada
- Pagefile garantido como gerenciado
- Serviços de baixo risco desativados (lista fixa e reversível)

**GPU**
- HAGS (build 22000+)
- Fullscreen exclusivo forçado

**Segurança**
- Pastas de jogos (Steam, Riot, Epic, Ubisoft, Battle.net) excluídas da varredura em tempo real

## O que ele NÃO faz

Deliberadamente fora, por não ter efeito mensurável ou por prejudicar:

- Tweaks de Nagle (`TcpAckFrequency`) — jogos usam UDP
- Desativar HPET ou forçar timer global
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

## Requisitos

- Windows 10 1809+ ou Windows 11
- PowerShell 5.1+
- Administrador para `apply` e `revert`

## Estrutura

```
bnqq.ps1              CLI
lib/Core.ps1          elevacao, log, backup, restore point
lib/Detect.ps1        deteccao de hardware, aplicabilidade, achados
lib/Tweaks.ps1        catalogo de tweaks, plano de energia, rede, servicos
config/profiles.json  perfis
docs/what-it-does.md  efeito e risco de cada tweak
```

## Aviso

Desativar HVCI reduz a proteção contra exploits de kernel. É uma troca consciente por desempenho. Use `desktop` ou `laptop` se preferir manter a proteção.

Testado em Windows 11. Em Windows 10, tweaks que exigem build 22000+ são ignorados automaticamente.
