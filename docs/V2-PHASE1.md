# BNQQ 2.0.0 — fase 1: vetores 1, 4 e 19

Esta entrega implementa sessao de CPU e recuperacao. Nao representa conclusao dos 20 vetores nem prova de ganho de FPS. Driver NVIDIA fica para outra fase; nao modifica configuracao do jogo.

## Vetor 1: core parking opcional

`-UnparkCpu` solicita somente `CPMINCORES=100` em AC no plano ativo. Leitura anterior, journal atomico e leitura posterior. DC, C-States/IDLEDISABLE, boost, PBO, temporizadores e atributos ocultos permanecem intactos. Se AC ja for 100, nao cria operacao redundante. Core parking e estados de ociosidade sao mecanismos diferentes.

Na maquina usada no desenvolvimento, o plano ja estava em AC=100 antes da fase: nao existe ganho novo atribuivel a reaplicar esse valor.

## Vetor 4: CPU Sets de aplicativos concorrentes

Usa `GetSystemCpuSetInformation`, `GetProcessDefaultCpuSets` e `SetProcessDefaultCpuSets`, sem hook ou driver adicional. Mapeia SMT por CoreIndex real, incluindo topologias com indices logicos intercalados. Seleciona os ultimos N nucleos fisicos para os apps escolhidos; preserva pelo menos dois fora desse grupo. Nao e particao exclusiva do cache L3 ou reserva de CPU para o jogo.

Lista explicita: msedge, chrome, firefox, Discord e OneDrive. Nao altera prioridade, afinidade rigida, processos de sistema ou do jogo. Respeita afinidades preexistentes e intersecciona CPU Sets ja definidos. Sem interseccao, registra e pula aquele processo. Limite de 128 candidatos; participantes fixos, sem WMI de inicio de processos, polling de novas tarefas ou purga de memoria.

Topologia hibrida, multigrupo, CPU Sets reservados, IDs duplicados e dados inconsistentes sao recusados, sem deduzir arquitetura pela placa-mae ou inventar fallback AMD/NVIDIA.

CPU Sets sao uma politica de posicionamento. Threads com selecao explicita podem sobrepor o padrao do processo; afinidade rigida continua tendo precedencia. Nao medir o valor solicitado como se fosse throughput ou FPS. Dependendo da concorrencia, a restricao pode prejudicar responsividade de apps selecionados; e um experimento opcional e reversivel.

## Vetor 19: recuperacao e execucao noturna

Journal v2 passa a admitir CPU Sets somente dos aplicativos listados e AC=100 para CPMINCORES. Valida identidade PID/nome/inicio e transicoes, usa handle antes da escrita e verifica resultado. Reconhece processo encerrado ou PID reutilizado. Se CPU Sets forem alterados externamente, preserva a alteracao e deixa pendencia, sem sobrescrever.

Sessao normal e falhas chamam restauracao em `finally`. Durante o jogo, consulta saude a cada dez segundos, alem da verificacao apos cada operacao. WHEA novo, Kernel-Power 41 novo ou falha na leitura provoca tentativa de rollback. Eventos historicos e HeavyQA continuam bloqueando aplicacao inicial.

`Incident-Rollback.ps1` agora usa o roteador de recuperacao de todos os tipos conhecidos. CPU Sets/processos do usuario podem ser recuperados sem exigir administrador antecipadamente; energia e registro ainda exigem permissao. Erros sao escritos em `%LOCALAPPDATA%\BNQQ\data\bnqq-night-log.txt`. Nao sao convertidos em sucesso.

Queda de energia/BSOD encerra o codigo e impede rollback imediato. Journals persistem para recuperacao posterior. CPU Sets de processos encerrados desaparecem com eles; uma alteracao de plano de energia pode persistir e precisa de recuperacao. Nao ha garantia de recuperacao instantanea ou de ausencia de conflito com outro software.

## Entradas operacionais

```powershell
.\bnqq.ps1 cpu-session -SessionApps msedge -BackgroundCores 2
.\bnqq.ps1 cpu-session -CpuAction run -SessionApps msedge -BackgroundCores 2 -UnparkCpu
.\bnqq.ps1 cpu-session -CpuAction restore -BackupFile JOURNAL
.\bnqq.ps1 phase-health
.\scripts\Invoke-NightPhase1.ps1 -Apply -UnparkCpu
```

Sem `-Apply`, o runner noturno prepara plano e salva registro proprio; nao aplica ajustes. Com `-Apply`, usa os mesmos gates de WHEA/HeavyQA do produto. Faz verificacao final de saude e chama `Incident-Rollback.ps1` somente com journal desta execucao, quando existir. Nunca escolhe backup antigo para restaurar por adivinhacao. Nenhum prompt, reboot ou elevacao automatica; permissoes insuficientes sao erro registrado.

## Validacao e limites de anti-cheat

Testes de fixtures cobrem SMT intercalado, CPU hibrida/reservada/multigrupo, nao expansao de restricoes, no-op, AC/DC, write-ahead, falha apos escrita, conflito externo e rollback por WHEA. A regressao FrameBench permanece exigida.

No Windows da maquina alvo, um processo de teste teve CPU Sets aplicados/lidos/restaurados; estado originalmente vazio foi restaurado e prioridade/afinidade preservadas. O filho criado durante o teste nao herdou o CPU Set padrao. Esse resultado nao garante o comportamento de programas que explicitamente propagam suas proprias preferencias aos filhos.

Durante a atribuicao, 128 amostras de `GetCurrentProcessorNumber` no processo de teste ficaram nos processadores logicos 12, 13, 14 e 15, correspondentes aos CPU Sets selecionados nessa maquina. Isso confirma posicionamento real nessa amostra; nao mede ganho de FPS, throughput ou ausencia de stutter.

Nao usa injecao no jogo, MSR, alteracao de firmware ou driver de kernel adicional. Isso nao equivale a certificacao de FACEIT/Vanguard: acesso negado e recusado, sem contornar protecoes. Nenhum ganho de p99, 0.1% Low ou latencia foi certificado nesta fase.

Referencias primarias: [CPMinCores](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/options-for-core-parking-cpmincores), [CPU Sets](https://learn.microsoft.com/en-us/windows/win32/procthread/cpu-sets), [estrutura de topologia](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-system_cpu_set_information), [atribuicao por processo](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setprocessdefaultcpusets).
