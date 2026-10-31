# Controle dinamico de prioridade — 2.0.6

O modo `focus -FocusPolicy Priority` reduz para BelowNormal a prioridade de CPU
de processos escolhidos de Edge, Chrome, Firefox e OneDrive. Preserva CPU Sets,
afinidade, clocks, memoria, I/O e a prioridade do jogo. Funciona sem depender da
marca da GPU. Nao e limitador percentual de CPU nem garante FPS maior.

O controlador precisa observar o mesmo PID/horario de criacao em duas amostras,
com consumo medio de pelo menos 25 ms de CPU por segundo (2,5% de um processador
logico). Amostra a cada cinco segundos e aplica no maximo duas mudancas por
ciclo, apenas enquanto CS2 ou Valorant esta em primeiro plano.

O modo e explicito; o padrao antigo CpuSets permanece disponivel. A previa
informa a politica e os apps escolhidos, sem abrir handles dos participantes.
Discord, utilitarios de perifericos, sistema, jogo e anti-cheat nao sao alvos.
Somente processos do usuario e da sessao do controlador sao admitidos.

Desde 2.0.9, tres amostras consecutivas com menos de 5 ms de CPU/segundo em
todos os participantes observados liberam o periodo de prioridade. Ha 15 segundos
de intervalo antes de novas admissoes, evitando alternancia continua. Processo
novo ou contador regressivo nao e prova de ociosidade. A admissao continua em
25 ms/segundo; sao limiares distintos de histerese, nao limites percentuais de CPU.
O cooldown e monotonicamente cronometrado. CPU Sets mantem o comportamento anterior.
Restauracao pode envolver todos os participantes; limite de duas mudancas por
ciclo se refere a admissoes, nao a atrasar a recuperacao.

## Estado anterior e recuperacao

Cada participante tem prioridade anterior salva em journal antes da escrita,
identidade PID/horario verificada no handle e leitura posterior. Alt+Tab encerra
o periodo de intervencao e restaura os participantes alterados; o retorno ao
jogo exige novas amostras. Saida cooperativa e erros passam pela restauracao.
Prioridades alteradas externamente nao sao sobrescritas na recuperacao.
O journal Schema 2 tambem aparece na recuperacao normal, sem exigir admin
antecipadamente quando contem apenas operacoes de processos do proprio usuario.

O Windows permite que filhos criados por um processo BelowNormal herdem essa
classe. Um filho que ja nasceu BelowNormal nao tem prioridade anterior conhecida;
o BNQQ preserva esse estado em vez de inventar Normal. Pode ser necessario reabrir
o aplicativo para eliminar essa heranca. O controlador nao encerra aplicativos.

Um crash de Windows impede finally. Journals duraveis permitem recuperacao,
mas nao autorizam prometer restauracao automatica de todo estado apos perda de
energia. PID reutilizado e processo encerrado nunca recebem prioridade antiga.

## Validacao e limites

Testes simulam descoberta de processos, Alt+Tab, troca de PID, erro apos a escrita,
WHEA, conflito externo e restauracao. A CLI tambem tem teste de previa sem jogo.
Nenhuma carga de stress ou captura real e necessaria para esses testes de codigo.
Aplicacao real continua condicionada ao gate de estabilidade/HeavyQA.

Possivel beneficio depende de concorrencia de CPU; esta entrega nao demonstra
ganho de FPS, p99 ou latencia. Nao testa nem garante aceitacao por anti-cheat.

Base tecnica: [prioridades do Windows](https://learn.microsoft.com/en-us/windows/win32/procthread/scheduling-priorities)
e [SetPriorityClass](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setpriorityclass).
Usa classe BelowNormal suportada, sem PROCESS_MODE_BACKGROUND_BEGIN em outro processo.
