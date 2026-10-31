# Sessao competitiva integrada — 2.1.1

compete plan faz analise somente leitura de CPU/GPU e readiness, mostra os apps
e as acoes propostas. A GPU observada e classificada pelo vendor PCI, com versao
de driver; inventario falho fica Partial/Unknown, sem assumir AMD ou NVIDIA por
placa-mae SMBIOS. O perfil de recursos funciona sem ajustes especificos de GPU.
NVIDIA conserva o comando NVAPI separado, com verificacoes de assinatura/perfil.
AMD/Intel nao recebem parametros NVIDIA; nao ha promessa de driver tuning universal.

compete run usa um unico controlador focus Priority. O default seleciona Edge,
Chrome, Firefox e OneDrive para prioridade dinamica somente quando medidos ocupados.
Nao altera configuracao do jogo, clocks, energia, GPU, cache de shaders, NIC,
BCD, VBS, dispositivos ou IRQs. So controles de processos do usuario/sessao atual.
Heranca de prioridade por filhos continua com os limites descritos em BACKGROUND-BUDGET.

PauseSearch e DeferMaintenance sao opcionais e preservam os controles/limites
existentes. NetworkApps habilita explicitamente lease de upload por aplicativo
de sincronizacao admitido; UploadKbps e a taxa solicitada por politica. Sem
NetworkApps, nenhuma politica de upload e criada. QoS/manutencao podem exigir
administrador; prioridades proprias nao exigem admin antecipadamente.

Prioridades sao restauradas no Alt+Tab/ociosidade. Os leases de upload/manutencao
permanecem enquanto o jogo existe, ate stop cooperativo, erro ou fim da sessao.
Nao ha sobreposicao de dois controladores disputando o lock. Falha de um recurso
dispara tentativas de cleanup independentes dos demais em finally. Um crash do SO
impede finally: backups ficam disponiveis em recover. Politicas alteradas externamente
nao sao apagadas. Limite de upload nao limita downloads nem garante menor ping.

compete stop/status usa a identidade do controlador focus. O run verifica a saude
real novamente; uma previa com Ready=true nao autoriza ignorar WHEA posterior.
Nenhuma tarefa de inicializacao ou aplicacao de perfil e instalada automaticamente.

## Recuperacao

Incident-Rollback agora importa o adaptador BackgroundBudget. Um teste de
integracao percorre o script real com identidade encerrada, sem escrever em
processos. Recuperacao de journal NIC Activated usa restore-active para restaurar
tambem o estado reportado pelo driver, com possivel desconexao breve. Esta mudanca
de codigo nao executa rollback da NIC automaticamente nem altera o ajuste mantido.

## Limites

O produto fornece automacao verificavel de recursos concorrentes; nao conclui
que ela aumenta FPS na ausencia de concorrencia. O inventario de GPU nao valida
firmware nem compatibilidade anti-cheat. Nenhum perfil garante zero delay/stutter.
O mapa dos 20 vetores registra tambem medidas nao adotadas e pendencias de medicao.
