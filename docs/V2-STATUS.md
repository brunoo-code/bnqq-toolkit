# Estado dos 20 vetores — 2.1.2

Implementar uma funcao nao demonstra ganho de desempenho. Nenhum vetor abaixo
autoriza aplicar ajustes em hardware com WHEA ativo. O inventario deve separar
suporte detectado, alteracao efetiva, verificacao de estado e beneficio medido.

| Vetor | Entrega / decisao atual |
|---|---|
| 1 CPU/energia | CpuSession/Optimize: core parking opcional com journal; estados de idle nao mudam por padrao. Sem escrita de MSR/ACPI. |
| 2 GPU | CompetitionSession inventaria fornecedor PCI/versao. NVIDIA via NVAPI assinada em comando opt-in separado; AMD/Intel/Unknown ficam sem escrita de driver. |
| 3 RAM | StorageMemory observa pressao/commit; SyntheticLoad tem leituras verificadas limitadas. Sem purga, pagefile off ou LPIM global. |
| 4 SMT | CpuSession: CPU Sets baseados em topologia nativa para apps escolhidos. Nenhum isolamento universal par/impar; sem restringir o jogo por padrao. |
| 5 NVMe | StorageMemory: duas tolerancias documentadas de StorNVMe, opcionais e reversiveis. Sem MSI/IRQ ou cache de escrita generico. |
| 6 Rede | NicPolicy: checksums suportados e ativacao verificada. QoS opcional por app pode coexistir com prioridade/manutencao sob um controlador. Sem prometer ping menor. |
| 7 Prioridades | Priority adaptativo com atividade medida, liberacao idle, histerese, cooldown e identidade/SID/sessao. Sem RealTime ou MMCSS ficticio. |
| 8 DWM/MPO | Diagnostico e modos de apresentacao no FrameBench. Nenhuma desativacao global de DWM ou MPO por padrao. |
| 9 USB | PlatformAudit segue ancestrais de interfaces Mouse/Keyboard com cache/limites/ciclos. Polling nao e medido; IRQ/dispositivos nao sao modificados. |
| 10 Servicos | Maintenance: lease temporario do WSearch, respeitando dependentes e estado inicial. Sem poda global de servicos. |
| 11 DPC/ISR | DriverAudit e DpcAnalysis offline de eventos individuais normalizados, com perda/unidades/overlap verificados. Coleta ETW e conversao automatica WPA/ETL pendentes. Sem desabilitar dispositivos. |
| 12 VBS | PlatformAudit observa estado DeviceGuard. Sem desligamento/bypass de VBS/HVCI, TPM, Secure Boot ou alteracao de requisitos anti-cheat. |
| 13 Shaders | Cache preservado. Limpeza antes de cada jogo nao e uma otimizacao de stutter; manutencao por corrupcao requer fluxo separado. |
| 14 Watcher | Watcher limitado; FocusSession adaptativo usa CPU medida e restaura prioridade apos atividade baixa. compete integra recursos sem controladores concorrentes. |
| 15 BIOS/PBO | Observado/declarado separados; PBO/CO nao medidos, sem escrita BIOS/FCLK/tensao. Timers BCD somente leitura; nao inferir clock efetivo pela presenca de HPET. |
| 16 Shell/gravar | Perfil recording-off com backup. Sem encerrar Explorer ou alterar preferencias visuais silenciosamente. |
| 17 Tarefas | Maintenance: duas tarefas admitidas, lease reversivel e recusa de conflitos externos. Sem apagar atualizadores ou manutencao geral. |
| 18 FrameBench | FrameBench real e gerador/medidor C# sintetico separados. Referencia de frametime nao calibra trabalho de engine/GPU. WHEA bloqueia novas cargas/capturas. |
| 19 Recuperacao | Journals, conflitos, PID/start e cleanup independente CPU/manutencao/QoS. Incident-Rollback cobre BackgroundPriority; NIC Activated usa restore-active. Crash ainda impede finally. |
| 20 Publicacao | Fontes comuns nos dois repositorios, builds e testes com adaptadores simulados. Capturas, eventos e dados pessoais nao entram na distribuicao publica. |

## O que falta para demonstrar beneficio

O ensaio sintetico nao reproduz prefire nem certifica estabilidade absoluta.
Melhoria de FPS/frametime exige PC estavel e comparacao controlada no jogo.
Instrumentacao ETW automatizada, driver tuning AMD/Intel e polling USB real
nao estao implementados. Medidas explicitamente nao adotadas nao sao anunciadas
como funcoes prontas. Esta campanha nao prova superioridade sobre produtos pagos.

## Limites da etapa 2.0.5

Os testes de software usam relogio, processos, PresentMon e adaptadores simulados.
Nao executam partida, captura real, stress de CPU/GPU/RAM ou alteracao de NIC.
O patch reduz trabalho redundante do controlador; ainda nao ha ganho de FPS
demonstrado. Uma captura anterior nao se torna prova causal de melhoria.

WHEA fatal deve suspender a campanha de benchmarks ate investigar estabilidade.
Aguardar 72 horas ou apagar eventos nao corrige a causa. Nao alterar PBO/CO/RAM
automaticamente nem prometer que um teste curto de carga certifique todo o PC.

## Etapa 2.0.6 (fase 7)

Vetores 7/14/19: modo Priority dinamico para navegadores/OneDrive escolhidos,
com amostragem, verificacao de usuario/sessao e journal de recuperacao.
O modo nao altera CPU Sets/afinidades nem configura o jogo. Veja
[comportamento e limites](BACKGROUND-BUDGET.md). CLI privada corrigida para
declarar os parametros focus que ja eram referenciados pelo dispatcher.
Somente validacao de software nesta etapa; sem aplicacao real nem ganho medido.

## Etapa 2.0.7 (fase 8)

Vetores 9/11/18: inventario de drivers e infraestrutura offline de analise de
eventos DPC/ISR normalizados. A coleta ETW real e a conversao automatica de
WPA/ETL continuam pendentes; IRQs e dispositivos nao sao modificados.
Veja [contrato, procedencia e limites](DRIVERS-DPC.md). Sem ganho medido.

## Etapa 2.0.8 (fase 9)

Vetores 9/12/15/19: plataforma somente leitura (timers, ancestrais USB e VBS),
sem alteracoes de seguranca, firmware ou IRQ. WHEA 18 bloqueia recursos em
72h mesmo se pertencer a boot anterior. Revisao de fornecedores em
[ENGINEERING-REVIEW](ENGINEERING-REVIEW.md). Nenhuma superioridade medida.

## Etapa 2.0.9 (fase 10)

Vetores 7/14/19: prioridade adaptativa com liberacao apos atividade baixa,
histerese e cooldown; sessao legada verifica escopo e corrida de prioridade.
Sem aplicacao no host com WHEA, sem ganho de desempenho declarado.

## Etapa 2.1.0 (fase 11)

Vetores 3/18/19: gerador sintetico C# CPU/memoria com limites, contador verificado
e medidor do processo hospedeiro. Referencia FrameBench anexavel, sem equivalencia
de carga com o prefire. Nao executado neste host com WHEA recente.

## Etapa 2.1.1 (fase 12)

Vetores 2/6/7/10/14/17/19/20: perfil integrado de recursos com inventario
CPU/GPU por usuario, leases de upload opcionais sob o mesmo lock e cleanup
independente. Script Incident-Rollback cobre novo tipo de prioridade; NIC Activated
roteia restore-active. Sem alteracao do host, sem ganho de FPS demonstrado.
