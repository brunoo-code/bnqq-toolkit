# Consistência e teste de limite nativo (v2.3.2)

1% low é o inverso do tempo médio dos 1% de quadros mais lentos na implementação FrameBench. Não é FPS mínimo nem o inverso do p99. Uma média maior ou menor variância depois de limitar FPS não prova que os quadros lentos ficaram mais rápidos.

## Correção aplicada

O cfg gerado pelo `cs2-engine` v2.3.0/v2.3.1 continha `fps_max 0` e `fps_max_ui 120`. Isso podia desfazer limites escolhidos no perfil nativo do CS2. O template v2 da v2.3.2 remove essas duas atribuições; os limites passam a ser preservados. O rollback ainda reconhece journals históricos sem `ConfigVersion` e templates v1. Não alteramos backups antigos.

`framepacing` informa a inspeção do cfg gerenciado. Se identificar o template antigo e o limite solicitado entrar em conflito, recusa aplicar em vez de apresentar um limite como efetivo. Detecção indisponível ou cfg customizado não equivale a ausência de overrides. Outros autoexecs/launch options e limites do driver continuam podendo interferir.

Para perfis antigos, a aplicação de `cs2-engine` migra apenas arquivos gerenciados reconhecidos, mas também reaplica o preset gráfico escolhido: examine o plano antes. Não usamos essa migração para sobrescrever um cfg do usuário.

## Teste de 240 FPS

O menu 6 oferece limite de partida 240 e menu 120, ou somente menu 120 preservando a partida. Também é possível selecionar outro limite nativo pelo comando existente:

```powershell
.\bnqq.ps1 framepacing -CompetitiveAction plan -GameCap 240 -MenuCap 120
.\bnqq.ps1 framepacing -CompetitiveAction apply -GameCap 240 -MenuCap 120
.\bnqq.ps1 framepacing -CompetitiveAction restore -BackupFile 'JOURNAL_RETORNADO.json'
```

Isso é uma experiência de orçamento de quadros, **não uma otimização comprovada**. Limitar FPS pode deixar folga entre quadros e reduzir trabalho/consumo, mas também reduz FPS máximo e pode aumentar latência frente ao ilimitado. Não corrige compilação de shaders, erros de hardware, perdas de rede ou todas as esperas da engine. A [NVIDIA explica o papel de limitadores na fila CPU/GPU](https://www.nvidia.com/en-gb/geforce/news/reflex-low-latency-platform/), sem prometer que qualquer cap aumentará o 1% low.

## Critério para aceitar a mudança

Só manter como ganho medido após comparar rodadas equivalentes com 1% low, 0.1% low, p99/p99.9 e latência quando houver uma fonte válida. Informar também a redução intencional de FPS médio/máximo. Não calcular um “novo 1% low” artificial truncando um CSV antigo em 240 FPS.

Uma gravação com GPU folgada durante quadros lentos sugere investigar CPU/engine/esperas, mas não identifica sozinha processo ou driver culpado. Campos de CPU podem ser derivados ou incompletos conforme runtime; uso de GPU amostrado a cada 500 ms não localiza microtravadas. [Limitações do PresentMon](https://github.com/GameTechDev/PresentMon).

As proteções por WHEA permanecem: não iniciamos captura ou estresse para validar este preset em hardware com erro recente. Alterar arquivos com o jogo fechado não confirma estabilidade. Não requer reiniciar Windows; vale na próxima abertura do CS2. Restauração usa os bytes anteriores, com proteção contra alterações externas.
