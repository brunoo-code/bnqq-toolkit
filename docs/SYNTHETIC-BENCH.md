# Gerador e medidor sintetico em C# — 2.1.0

O comando synthetic cria um experimento de CPU e leituras verificadas de memoria
com rajadas e pausas. Ele nao representa o mapa de prefire do CS2 nem mede FPS,
ping ou mouse-tela. A mesma media de GPU/FPS pode resultar de cargas diferentes.
Frametimes da captura anterior descrevem apresentacao de quadros, nao instrucoes
de CPU, shaders, fisica, bots ou acessos de assets suficientes para recriar o mapa.

## Implementacao

SyntheticLoad.cs cria ate 16 workers em background, limitados tambem pela
quantidade de CPUs disponiveis no coordenador. Cada worker aloca uma unica area
de 1 a 16 MiB (maximo total 256 MiB), inicializa um padrao deterministico e verifica
leituras pseudoaleatorias em blocos de 1024 indices. Contadores sao separados em
slots espacados e lidos atomicamente. Nao ha limpeza de RAM ou paginas bloqueadas.

O default e ate quatro workers, 30 segundos, ciclos de 100 ms com 50% de tempo de
rajada e dez segundos de cauda idle. Duty e um orcamento de tempo de parede;
nao garante a mesma porcentagem de uso de CPU. Inicializacao, preempcao, caches,
boost e instrumentacao influenciam o trabalho realizado. A duracao maxima de
120 segundos tambem e verificada internamente pelos workers em Stopwatch.

Nao ha renderizacao/GPU, I/O de disco de stress, injeção, driver, afinidade,
prioridade, timer resolution ou alteracao de energia/clock. A classe nao executa
por ser importada/compilada. Workers so iniciam por run depois dos gates.

## Coordenador e dados

WHEA recente/telemetria inacessivel impede iniciar. Jogo/captura em execucao ou
outro controlador BNQQ tambem impede o ensaio. O controlador verifica saude a
cada segundo e durante a cauda idle, encerra cooperativamente e registra sucesso
ou falha em journal JSON local. A deteccao de eventos e reativa: nao impede um
travamento antes de o Windows registrar o erro. Nao existe certificado HeavyQA
nem garantia de estabilidade absoluta emitida por este comando.

Cada amostra informa tempo monotonicamente decorrido, delta de CPU do processo
hospedeiro, equivalencia em nucleos, porcentagem normalizada pelas CPUs disponiveis,
working set do hospedeiro e progresso verificado. O hospedeiro inclui PowerShell
e consultas do log; nao e medicao isolada das threads, GPU ou temperatura.

synthetic sem run apenas mostra o plano. Os argumentos SyntheticThreads,
SyntheticSeconds, SyntheticDuty, SyntheticCycleMs, SyntheticMemoryMiB e
SyntheticIdleSeconds controlam limites explicitos. SyntheticReference aceita
resultado FrameBench schema 2, limitado a 4 MiB, guarda hash/cenario/metricas
como referencia e registra UsedToSetLoadParameters=false. Nao usa frametime para
inventar duty ou afirmar equivalencia com prefire. Para calibracao futura seriam
necessarios dados adicionais de trabalho/tempo de CPU e GPU e validacao no jogo.

## Testes realizados nesta entrega

Compilacao real de C#, fixture pequeno de verificacao do kernel e erro de memoria
simulado. Coordenador com workers/relogio/telemetria simulados: limites, WHEA
antes/durante, jogo ativo, inicio parcial, parada, cauda idle e persistencia.
Nenhum worker real e iniciado na suite local. Ha fixture restrito ao CI remoto:
um worker, 1 MiB, 10% duty por um segundo para verificar deadline/progresso,
mais parada cooperativa precoce. Isso nao e ensaio de desempenho/estabilidade.
O ensaio pesado local permanece
bloqueado quando existe WHEA fatal recente; nao ha resultado sintetico de desempenho
do PC apresentado como medido nessa situacao.
