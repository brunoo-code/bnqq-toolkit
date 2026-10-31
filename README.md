# BNQQ Toolkit Public 2.0.6

Diagnóstico local e experimentos reversíveis para Windows PowerShell 5.1 x64, com foco em CS2 e Valorant. **Esta versão retira os pacotes de tweaks legados.** Não promete zero delay, estabilidade absoluta ou ganho de FPS.

Núcleo compartilhado com o repositório privado `optimizer-bnqq`, com atualizações publicadas em ambos. A distribuição pública não inclui gate de HWID/licença, chave de assinatura ou preset pessoal. O histórico público foi preservado; não houve merge de objetos Git privados.

## Começar sem modificar o Windows

```powershell
.\bnqq.ps1 help
.\bnqq.ps1 audit
.\bnqq.ps1 topology
.\bnqq.ps1 network
.\bnqq.ps1 display
.\bnqq.ps1 apps
.\bnqq.ps1 apply -Profile recording-off -DryRun
```

O inventário informa dados observados e declarados separadamente. O arquivo `config/hardware.json` vem sem preset pessoal. Preencha declarações opcionais apenas se souber a configuração real. FCLK e placa não são certificados por WMI. Identificadores SMBIOS inconsistentes não autorizam mudanças de firmware nem são “corrigidos” por este software.

## Experimentos disponíveis

* `recording-off`: política documentada `AllowGameDVR=0`. Desativa gravação, uma mudança funcional; não há ganho presumido.
* `latency`: somente orientação por padrão. `-ForceDeepIdleDisable` solicita explicitamente `AC IDLEDISABLE=1`, sem mudar DC, boost, coalescência ou resiliency. É experimento avançado, com risco de consumo/temperatura, não recomendação para este hardware.
* `watch`: observa por padrão. `-AboveNormal` e `-PinPhysical` são opcionais e exigem QA. Não limpa RAM, suspende apps, trava clocks, solicita timer ou modifica background. `-ObserveWmi` habilita um observador limitado; o Lasso antigo que alterava processos foi retirado.
* `apps -CleanLegacyFlags`: remove apenas os dois tokens Chromium invertidos, depois de registrar os argumentos exatos. Use primeiro `-DryRun`. Não executado automaticamente.

Aplicações exigem histórico WHEA acessível sem eventos relevantes nas últimas 72 h, HeavyQA v2 aprovado nas últimas 24 h para o mesmo boot/configuração, ausência de journal pendente. Sem autoelevação; execute explicitamente em terminal administrativo após revisar o código. Restore nunca exige licença nem aprovação do QA.

```powershell
# Executar apenas depois da revisão: carga real por pelo menos 10 minutos.
.\bnqq.ps1 heavyqa -HeavyMinutes 10
.\bnqq.ps1 apply -Profile recording-off
.\bnqq.ps1 restore -BackupFile 'CAMINHO_EXIBIDO_DO_JOURNAL'
```

HeavyQA mede uma carga limitada: SHA-256 verificado por thread, escrita/leitura contínua e verificada em arquivo temporário, WHEA a cada dois segundos e cauda idle monitorada. Não substitui teste de RAM, GPU, boost por núcleo ou diagnóstico de CO/PBO. Alterações de BIOS nem sempre são observáveis; reinicie e repita o QA após qualquer mudança. Um PASS não é atestado de estabilidade absoluta.

## Estado e recuperação

Dados ficam em `%LOCALAPPDATA%\BNQQ\data`, fora do payload de build. Cada alteração admitida tem captura anterior, journal atômico antes da escrita e verificação posterior. Restore trabalha em ordem inversa, é repetível e recusa conflitos externos. Processos usam PID **e horário de criação**, nunca apenas o PID.

Há suporte a registro auditado, IDLEDISABLE, argumentos de atalhos auditados e estado dos jogos. Serviços, DNS, BCD, exclusões Defender, AppX e demais alterações globais não são mais escritos. Portanto não existem novos estados desses tipos a restaurar. Journals antigos não são promovidos a “completos”: veja [migração](docs/MIGRATION.md).

## Medir antes de concluir

```powershell
.\bnqq.ps1 framebench -Scenario 'mapa-demo-trecho' -SettingsHash 'hash-configs' -ExperimentId 'teste-01' -Variant baseline
# Intercale no mínimo três baselines e três candidatas, com o mesmo cenário aquecido.
.\bnqq.ps1 compare -CaptureFiles A1.json,B1.json,A2.json,B2.json,A3.json,B3.json
```

PresentMon deve ser instalado separadamente. Há filtros `-SwapChain`, `-FrameProcess` e caminho explícito `-PresentMonPath`; nenhum stream é escolhido silenciosamente. Um acionamento de hotkey por rodada. Múltiplos CSVs/streams exigem seleção explícita.

Relatórios: FPS médio, 1%/0,1% low pela média dos frames mais lentos, desvio padrão populacional, p95/p99/p99,9 por nearest-rank, eventos acima de 16,667/33,333 ms e taxa por minuto. Esses limites são definições de relatório, não limiares universais de percepção. FPS/present não é mouse-tela nem hitreg.

Comparação exige contexto idêntico, ferramenta idêntica e rodadas intercaladas; só aponta vantagem local quando todos os p99 candidatos ficam abaixo dos baselines sem regressão média de p99,9 ou FPS >1%. Não é teste de significância formal nem prova universal. Metadados informados pelo operador precisam refletir o ensaio real.

## Validação e build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Regression.ps1
.\build.ps1
```

Os testes usam adaptadores de mutação simulados, fixtures CSV, topologia em leitura e um worker curto em arquivo temporário. Não aplicam otimizações no host. CI executa essa suíte no Windows. O build verifica hashes do payload e preserva caches anteriores e dados duráveis. O build público não tem opção de embutir licença; keygen e módulo privado não são distribuídos. O launcher continua exigindo UAC, mas não aplica nada ao abrir.

O build público não contém chave de assinatura. Nenhum dado de capturas ou identificador local é publicado automaticamente.

Veja os [12 módulos](docs/MODULES.md), o [plano com linhas anteriores](docs/PATCH_PLAN_1.8.3.txt), as [limitações e migração](docs/MIGRATION.md) e as [fontes primárias](docs/SOURCES.md).

## Comparacao com referencia existente

Veja [sincronizacao publica e framebench -Effective](docs/PUBLIC_SYNC.md). O modo clean altera temporariamente apenas prioridade/afinidade do jogo; nao restaura o Windows ao estado de fabrica. Uma unica dupla de capturas nao comprova eficacia.

Perfil grafico reversivel CS2: veja [docs/COMPETITIVE.md](docs/COMPETITIVE.md). O comando competitive altera apenas MSAA com backup; nao libera tweaks bloqueados por WHEA.

Atualizacao do motor 1.8.4: [modulos FPS](docs/FPS-1.8.4.md), caps reversiveis de menu/partida e gates contra regressao de lows/jitter. Nenhum ganho percentual demonstrado.

Motor 1.8.5: sessao de prioridade opt-in e recuperacao unificada. Veja [docs/SESSION-1.8.5.md](docs/SESSION-1.8.5.md). Sem ganho de FPS demonstrado.

1.8.6: migracao seletiva de IFEO legado baseada em snapshots escolhidos, sem reset presumido. Veja [docs/LEGACY-1.8.6.md](docs/LEGACY-1.8.6.md).

1.8.7: sessao temporaria de upload para apps de sincronizacao, com criacao/verificacao/remocao de politicas QoS, recuperacao e regras de estabilidade. Menu 10; veja [docs/NETWORK-SESSION.md](docs/NETWORK-SESSION.md). Nenhum ganho de FPS ou ping presumido.

2.0.0 fase 1 (vetores 1/4/19): CPU Sets de apps concorrentes, core parking AC opcional e rollback monitorado. Veja [docs/V2-PHASE1.md](docs/V2-PHASE1.md). Nao representa os 20 vetores concluidos ou ganho de FPS certificado.

2.0.1 fase 2 (vetores 2/13/18): backend NVIDIA por perfil existente, shader cache preservado e telemetria GPU nativa opcional no FrameBench. Menu 12; veja [docs/V2-PHASE2.md](docs/V2-PHASE2.md). Sem ganho de FPS presumido.

2.0.2 fase 3 (vetores 3/5/6): memoria nativa, politica StorNVMe opcional e checksums IP/UDP por capacidade do driver, com configuracao sem restart de rede. Menus 13/14; veja [docs/V2-PHASE3.md](docs/V2-PHASE3.md). Sem ganho de FPS presumido.

### Fase 4: concorrencia durante o jogo

Modo `focus`: CPU Sets de background apos atividade medida, restauracao no Alt+Tab, indexador e manutencao temporarios opt-in. Sem alvo implicito nem ganho de FPS presumido. [Comportamento, limites e rollback](docs/V2-PHASE4.md).

### Fase 5: da preparacao a aplicacao

`readiness` separa historico WHEA de falhas neste boot. Recursos reversiveis exigem novo HeavyQA schema 3; energia/clocks mantem a regra de 72h. O atestado de recursos acompanha hardware e implementacao do teste, sem vencer a cada novo modulo. `nic -NicAction activate` aplica a configuracao salva com reset explicito do adaptador e leitura do driver; `restore-active` restaura tambem o estado carregado. [Detalhes e limites](docs/V2-PHASE5.md).

## Base 2.0.5

O controlador focus evita reconstruir o plano CPU para participantes ja tratados no mesmo periodo de foco. FrameBench recusa WHEA recente antes de iniciar coleta e rejeita resultados associados a incidentes novos. Nenhum ganho de FPS e presumido. Veja o estado de cada vetor em [V2-STATUS](docs/V2-STATUS.md).

## Etapa 2.0.6 - prioridade dinamica

Novo modo focus Priority: reduz a prioridade de navegadores e OneDrive escolhidos somente apos medir atividade de CPU, com restauracao no Alt+Tab/saida. Nao restringe afinidades nem altera configuracoes do jogo. Veja comportamento, limites de heranca de processos e recuperacao em [controle de background](docs/BACKGROUND-BUDGET.md). O modo CpuSets continua sendo o padrao da CLI. Nenhum ganho de FPS foi demonstrado nesta entrega.
