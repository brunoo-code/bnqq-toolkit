# Estado dos 20 vetores — 2.0.5

Implementar uma funcao nao demonstra ganho de desempenho. Nenhum vetor abaixo
autoriza aplicar ajustes em hardware com WHEA ativo. O inventario deve separar
suporte detectado, alteracao efetiva, verificacao de estado e beneficio medido.

| Vetor | Entrega / decisao atual |
|---|---|
| 1 CPU/energia | CpuSession/Optimize: core parking opcional com journal; estados de idle nao mudam por padrao. Sem escrita de MSR/ACPI. |
| 2 GPU | GpuDriver: NVIDIA via NVAPI assinada e perfil existente, com backup. AMD/Intel nao recebem parametros NVIDIA; nao ha implementacao de escrita equivalente para esses drivers. |
| 3 RAM | StorageMemory: pressao e commit observados. Sem purga automatica, pagefile desativado ou concessao indiscriminada de Lock Pages. |
| 4 SMT | CpuSession: CPU Sets baseados em topologia nativa para apps escolhidos. Nenhum isolamento universal par/impar; sem restringir o jogo por padrao. |
| 5 NVMe | StorageMemory: duas tolerancias documentadas de StorNVMe, opcionais e reversiveis. Sem MSI/IRQ ou cache de escrita generico. |
| 6 Rede | NicPolicy: checksums IP/UDP suportados pelo driver, stage/activate/restore e verificacao de rotas. NetworkSession: QoS temporario por app selecionado. Sem prometer ping menor. |
| 7 Prioridades | GameSession: prioridade de apps escolhidos e restauracao por identidade. Sem RealTime nem perfil MMCSS ficticio: registrar uma chave nao associa automaticamente o jogo a uma tarefa AVRT. |
| 8 DWM/MPO | Diagnostico e modos de apresentacao no FrameBench. Nenhuma desativacao global de DWM ou MPO por padrao. |
| 9 USB | Sem alteracao automatica de IRQ/polling. Exige identificar controlador compartilhado e medir o custo do periferico; nao inferir pela marca. |
| 10 Servicos | Maintenance: lease temporario do WSearch, respeitando dependentes e estado inicial. Sem poda global de servicos. |
| 11 DPC/ISR | Pendente de coleta ETW especifica e atribuicao por driver; FrameBench nao mede DPC. Nao desabilitar dispositivos por suposicao. |
| 12 VBS | Nao implementado desligamento/bypass automatico. Nenhuma exclusao de seguranca ou alteracao de requisitos de anti-cheat. |
| 13 Shaders | Cache preservado. Limpeza antes de cada jogo nao e uma otimizacao de stutter; manutencao por corrupcao requer fluxo separado. |
| 14 Watcher | Watcher limitado; FocusSession amostra carga dos apps e limita mudancas. 2.0.5 evita reconstruir o plano para participantes ja tratados no mesmo periodo de foco. |
| 15 BIOS/PBO | Inventario observado/declarado separado; sem escrita de BIOS, CO, FCLK, tensao ou fallback baseado em SMBIOS suspeito. |
| 16 Shell/gravar | Perfil recording-off com backup. Sem encerrar Explorer ou alterar preferencias visuais silenciosamente. |
| 17 Tarefas | Maintenance: duas tarefas admitidas, lease reversivel e recusa de conflitos externos. Sem apagar atualizadores ou manutencao geral. |
| 18 FrameBench | Percentis, lows, jitter e comparacao controlada; GPU opcional. 2.0.5 recusa captura com WHEA recente antes de carregar NVAPI/PresentMon; incidente novo impede publicar resultado valido. |
| 19 Recuperacao | Journals antes da escrita, restauracao seletiva com verificacao de conflito. Um travamento impede finally; consultar recuperacao apos boot, sem presumir sucesso. |
| 20 Publicacao | Fontes comuns nos dois repositorios, builds e testes com adaptadores simulados. Capturas, eventos e dados pessoais nao entram na distribuicao publica. |

## Limites da etapa 2.0.5

Os testes de software usam relogio, processos, PresentMon e adaptadores simulados.
Nao executam partida, captura real, stress de CPU/GPU/RAM ou alteracao de NIC.
O patch reduz trabalho redundante do controlador; ainda nao ha ganho de FPS
demonstrado. Uma captura anterior nao se torna prova causal de melhoria.

WHEA fatal deve suspender a campanha de benchmarks ate investigar estabilidade.
Aguardar 72 horas ou apagar eventos nao corrige a causa. Nao alterar PBO/CO/RAM
automaticamente nem prometer que um teste curto de carga certifique todo o PC.
