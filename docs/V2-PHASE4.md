# v2.0.3 - concorrencia durante a partida (vetores 10, 14 e 17)

## Modo Focus: comportamento concreto

O comando `focus` combina tres experimentos opcionais. Nenhum modifica os arquivos,
prioridades ou afinidade rigida do CS2/Valorant. Nenhum suspende ou mata aplicativos.
O planejamento e a importacao dos modulos nao aplicam o perfil.

1. **Background com atividade medida.** Apps explicitamente escolhidos na lista
   auditada sao amostrados a cada cinco segundos. CPU Sets so sao aplicados quando
   o processo consumiu pelo menos 25 ms de CPU por segundo na ultima janela. Esse
   numero usa o tempo total de CPU do processo, sem confundir porcentagem do sistema
   com porcentagem de um processador logico. Processos novos precisam de duas amostras. O SID do proprietario e a sessao
   interativa sao conferidos nativamente: processos de outros usuarios/sessoes nao
   recebem esse ajuste, inclusive no CPU Session anterior.
   A prioridade e a afinidade rigida originais continuam intactas.
2. **Indexacao opcional.** `-PauseSearch` para somente WSearch, de maneira cooperativa,
   se ele estava rodando e pode ser reiniciado sem mudar seu tipo de inicializacao.
   O controle nativo SCM recusa dependentes ativos; nao para servicos dependentes
   recursivamente. Um indexador ja desativado/parado nao e reativado nem contado como ganho.
3. **Manutencao opcional.** `-DeferMaintenance` impede novos disparos de ScheduledDefrag
   e SilentCleanup durante a sessao, somente se habilitadas, nao executando e sem
   condicao de ociosidade ja configurada. Ao fim restaura Enabled, conferindo hash da
   definicao completa, exceto o proprio Enabled. Nao reimporta XML nem apaga tarefas.
   Uma tarefa que iniciar antes da desabilitacao nao e interrompida.

O posicionamento usa a topologia real de CPU Sets ja introduzida na fase 1. Nao e
reserva exclusiva de nucleos, isolamento de cache L3 ou configuracao automatica de BIOS.
CPU hibrida/multigrupo/reservada continua recusada; um perfil so de manutencao nao
exige que a politica CPU Sets seja suportada. Nada infere a placa-mae pelo SMBIOS.

## Limites e recuperacao

- Participantes vivos: 128; mudancas: duas por janela de cinco segundos; entradas por
  periodo de foco: 512; periodos: 64. Atingir um limite encerra com restauracao.
- CPU Sets sao restaurados ao perder o foco do jogo, detectado a cada segundo. Ao
  recuperar o foco, a amostragem recomeca. PID e horario de criacao impedem confundir
  processos reutilizados. Restricoes preexistentes nunca sao ampliadas.
- WSearch/tarefas permanecem na mesma concessao durante Alt+Tab: nao reiniciar o
  indexador repetidamente. Restauracao ao fechar o jogo, pedido cooperativo de parada,
  limite da sessao (padrao 120 minutos, maximo 240), erro ou novo evento de saude.
- Escritas usam o journal atomico schema 2 antes da mudanca, leitura posterior e
  recuperacao unificada/Incident-Rollback. Definicao de tarefa/configuracao de servico
  alterada externamente gera conflito; nao e sobrescrita.
- Nao ha heartbeat duravel escrito a cada segundo. O marcador e gravado no inicio;
  a atividade e validada pelo PID/horario real do controlador. As estatisticas de
  amostragem ficam na memoria. Erros repetidos de leitura sao deduplicados (maximo 128).
- O limite de validade da sessao nao sobrevive a um encerramento forcado do host ou
  queda de energia. Nesses casos, os journals permitem recuperacao pela opcao 8; nao
  existe promessa de rollback automatico depois de uma falha fisica da maquina.
- Nao instalar tarefa elevada auxiliar, nao reiniciar o PC/conexao, nao alterar tipo
  de inicializacao de servico, nao desativar Windows Update, Defender, anti-cheats,
  audio ou dispositivos. SysMain/Wecsvc/DiagTrack nao recebem poda generica.

O apply exige HeavyQA recente e valido para boot/configuracao/codigo e ausencia de
WHEA recente. As partes de manutencao exigem administrador se ha algo para mudar.
Recuperacao nao exige novo HeavyQA. Nao limpar logs nem inventar fallback generico.

## CLI

```powershell
# Apenas visualizar
.\bnqq.ps1 focus -SessionApps msedge,chrome,OneDrive -PauseSearch -DeferMaintenance
# Sessao explicita, jogo ja aberto; nao inicia nem encerra o jogo
.\bnqq.ps1 focus -FocusAction run -SessionApps msedge,chrome,OneDrive -PauseSearch -DeferMaintenance
# Outra janela pode solicitar saida cooperativa
.\bnqq.ps1 focus -FocusAction stop
.\bnqq.ps1 focus -FocusAction status
```

O menu oferece a opcao 15. Nao ha alvo implicito nem tarefas de inicializacao criadas.
FrameBench recusa o controlador dinamico ativo para nao comparar intervencoes variaveis
como se fossem constantes. Para um A/B com CPU Sets fixos existe `cpu-session`.

## O que pode e o que nao pode melhorar

Pode reduzir concorrencia de CPU dos participantes ativos e evitar indexacao/manutencao
iniciadas durante a partida. Sem concorrencia real, essas mudancas podem nao trazer ganho.
Restringir um aplicativo pesado demais tambem pode piorar seu funcionamento. Todos sao
experimentos opt-in; o limiar de atividade nao prova melhora de frametime. Nao existe
ganho de FPS, p99 ou ping declarado nesta fase sem capturas comparaveis.

Na maquina do desenvolvedor, WSearch ja estava Stopped/Disabled e SilentCleanup ja
exigia ociosidade. A configuracao nao foi alterada nem apresentada como ganho novo.

## Fontes primarias e verificacao

- [SCM ControlService: dependentes ativos retornam erro 1051](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-controlservice).
- [CPU Sets: mecanismo do Windows](https://learn.microsoft.com/en-us/windows/win32/procthread/cpu-sets).
- [Desabilitar tarefa agendada](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/disable-scheduledtask).
- [Prioridade BelowNormal e modo background restrito ao proprio processo](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setpriorityclass).

Fixtures executam os caminhos reais de journal, XML, orquestracao e recuperacao,
com adaptadores de hardware simulados. Cobrem foco, CPU ociosa/ativa, novos processos,
PID reutilizado, limites, Alt+Tab, parada cooperativa, WHEA, escrita parcial, servico
pendente, tarefa em execucao/ociosa/desabilitada e conflitos externos. Nao sao um
benchmark do jogo nem substituem testes reais de frametime.
