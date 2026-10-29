# BNQQ Optimizer v1.1.0 — Guia do Menu (Para Pro-Players)

Este guia explica o que cada opção faz **na prática dentro do jogo**. Não é necessário entender de programação.

## Como usar em 4 passos

1. Abra o `BNQQ_Optimizer.exe` e aceite o UAC. Se aparecer "Licença Inválida", copie o HWID e solicite seu `license.key` ao desenvolvedor.
2. Rode **[1] Deep Scan** para ver o estado real da máquina.
3. Aplique um perfil: **`competitive`** para uso diário ou **`extreme`** para torneio/bench.
4. Deixe o **Game Watcher** ativo. Ele entra sozinho quando CS2/Valorant abre e sai quando fecha.

## Menu privado

| Opção | Benefício prático no jogo |
|---|---|
| **[1] Deep Scan** | Tira uma “foto” completa do PC: CPU, GPU, memória, rede, interrupções e energia. Mostra o que está roubando desempenho e o que já está correto. |
| **[2] Aplicar perfil** | Aplica um pacote pronto de ajustes. `competitive` é o equilíbrio para jogar; `extreme` libera tudo para torneio. |
| **[3] Reverter último apply** | Desfaz o último pacote aplicado. Use se algo ficar estranho ou antes de uma atualização grande do Windows. |
| **[4] Game Watcher** | O “piloto automático”: quando o jogo abre, aplica plano de energia, timer de 0,5 ms, prioridade, GPU no máximo, isolamento de background e limpeza de memória se necessário. Ao fechar, devolve tudo ao normal. |
| **[5] Relatório modular** | Dá uma nota por área (CPU, GPU, memória, rede, input, display). Serve para achar o gargalo antes de culpar o jogo. |
| **[6] Veredito (placebo x real)** | Mostra o que realmente funciona e o que é mito de fórum. Evita perder tempo com ajuste que não muda o 1% low. |
| **[7] Topologia USB** | Mostra se mouse/teclado estão na controladora da CPU ou do chipset. Porta certa = menos latência de input. |
| **[8] Memória / FCLK (1:1)** | Confere se a RAM está no melhor modo para o Ryzen. FCLK 1:1 reduz latência de memória e melhora a consistência dos frames. |
| **[9] Stress 30s + PBO** | Coloca a CPU sob carga e mostra se o clock cai por temperatura. Ajuda a saber se o cooler aguenta o jogo. |
| **[10] Estabilidade PBO (WHEA)** | Testa o Curve Optimizer por 3–5 minutos e avisa se aparecer erro de hardware. Se avisar, reduza o CO na BIOS. |
| **[11] Timer resolution** | Mostra o timer atual. Com o watcher, o jogo roda em 0,5 ms; isso reduz jitter de input e de rede. |
| **[12] QoS / DSCP 46** | Marca o tráfego dos jogos como prioridade para o roteador, se ele respeitar DSCP. Não reduz ping físico, mas ajuda quando há disputa na rede. |
| **[13] Audio / audiodg** | Tira o áudio do Windows do mesmo núcleo do jogo e desliga efeitos/spatial. Menos stutter em cenas com muito som. |
| **[14] Pro-Tier (rede/energia)** | Remove limite de rede do kernel, desliga suspensão seletiva USB e, se você aceitar, desativa o dynamic tick. O dynamic tick é opt-in porque pode derrubar FPS. |
| **[15] God-Tier (CFG/memória)** | Mantém kernel/drivers na RAM, sobe o quantum do jogo e pode desativar CFG **somente** nos dois jogos. CFG é opt-in por risco de anti-cheat. |
| **[16] Vanguard (IRQ/RSS/standby)** | Pina interrupções da GPU/rede em núcleos escolhidos, joga o background nos threads SMT e limpa a standby list se a RAM livre cair abaixo de 4 GB. É o pacote de consistência para o 0,1% low. |

## Menu público

O público tem a mesma base em outra ordem:

- **[1] Deep Scan** — diagnóstico.
- **[2] Aplicar perfil** — pacote de ajustes.
- **[3] Reverter** — desfaz o último apply.
- **[4] Game Watcher** — piloto automático.
- **[5] Relatório modular** — nota por área.
- **[6] Veredito** — real x placebo.
- **[7] Estabilidade PBO** — teste do Curve Optimizer.
- **[8] Timer resolution** — 0,5 ms com watcher.
- **[9] QoS / DSCP 46** — prioridade de rede.
- **[10] Audio / audiodg** — isolamento de áudio.
- **[11] Pro-Tier** — rede, USB e dynamic tick opt-in.
- **[12] God-Tier** — CFG, paging e prioridade.
- **[13] Vanguard** — IRQ, SMT e standby.
- **[14] QA: Stress Test In-Game** — engine falsa + carga C# e validação do watcher.
- **[15] Ultimate (Super Pack)** — faxina pós-formatação, MMCSS e ajustes opt-in.
- **[16] ACPI / HPET / TSC** — auditoria e TSC nativo via BCD.
- **[17] MSI / PCIe** — MSI e afinidade de GPU/rede.

## O que usar antes de uma partida

1. Feche abas e downloads pesados.
2. Rode **[1] Deep Scan** uma vez.
3. Confirme que o **Game Watcher** está ativo.
4. Abra o jogo. O watcher assume o resto.
5. Se for torneio, use `competitive` ou `extreme`; se for uso diário, `competitive`.

## O que a ferramenta não faz

- Não injeta código no jogo.
- Não instala driver não assinado.
- Não desativa anti-cheat, Secure Boot ou DEP.
- Não promete FPS de propaganda: mede, mostra e reverte.
- Dynamic tick, CFG por jogo e purge de standby são opt-in/condicionais; têm custo e risco explicados no painel.

**Regra de ouro:** se uma opção não melhorar o seu 1% low ou a sensação de input, reverta. O objetivo é consistência, não número bonito no menu.
