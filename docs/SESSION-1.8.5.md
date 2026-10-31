# Sessao competitiva e recuperacao 1.8.5

## O que muda

O menu [7] oferece uma sessao opt-in com participantes fixos. Apps escolhidos que
estavam em Normal, AboveNormal ou High passam a BelowNormal. Apps ja em prioridade
menor e apps nao escolhidos nao mudam. O jogo nao recebe prioridade, afinidade,
timer ou configuracao de memoria. Nao fecha programas nem altera seu conteudo.

O mecanismo tem efeito funcional no escalonamento de CPU. Nao garante FPS maior:
se nao houver disputa por CPU, pode nao ajudar; navegadores e chamadas de voz podem
ficar menos responsivos quando escolhidos. Nao reduz automaticamente uso de GPU,
rede, memoria ou prioridade de todas as threads MMCSS. Nao aplica EcoQoS nem
finge controlar frequencia de CPU. Escolha apps realmente dispensaveis na partida.

## Uso

Abra CS2 ou Valorant e escolha os aplicativos. A lista publica comeca vazia.
Nomes admitidos: msedge, chrome, firefox, Discord, OneDrive, LAMZU Aurora,
AJAZZ Driver. Editors, terminais, anticheat e componentes do Windows sao recusados.

```powershell
.\bnqq.ps1 session -SessionApps msedge,Discord -DryRun
.\bnqq.ps1 session -SessionAction run -SessionApps msedge,Discord
.\bnqq.ps1 session -SessionAction run -SessionApps msedge -FrameProcess VALORANT-Win64-Shipping.exe
.\bnqq.ps1 recover
.\bnqq.ps1 recover -BackupFile JOURNAL
```

Nao use a primeira linha como autorizacao para aplicar todas as demais: apps sao
exemplos. O menu [7] solicita explicitamente nomes e jogo, sem preset automatico.

## Ciclo de vida e falhas

* Exige HeavyQA valido no mesmo boot/configuracao e historico WHEA sem bloqueios,
  preservando a governanca existente. Esta versao nova invalida certificado de
  versao anterior por mudar os hashes. Restore nao exige HeavyQA aprovado.
* Captura identidade PID + criacao + nome e abre o handle antes de modificar a
  prioridade. Guarda estado anterior antes de cada escrita e verifica leitura.
* Maximo 128 participantes. Monitor consulta somente a identidade do jogo a cada
  dois segundos. Novos processos filhos nao entram automaticamente; nao existe
  WMI watcher de churn nem ajuste variavel em loop.
* Ao jogo sair, ou por erro controlado, finally tenta restaurar. Ctrl+C solicita
  interrupcao; confirme o estado pelo menu de recuperacao. Fechar/matar o processo
  do toolkit, queda de energia e crash podem impedir finally: nesse caso e preciso
  abrir novamente o toolkit e restaurar o journal. Nao ha auto-start persistente.
* Se um PID foi reutilizado, o novo processo nao e alterado. Se a prioridade foi
  mudada externamente, restaura apenas apos resolver o conflito; nao sobrescreve.
* Sessao com recuperacao pendente bloqueia nova sessao. Trava de estado impede
  dois escritores simultaneos; processos terminados sao marcados sem relancar apps.
* Backups nao contêm comandos para executar. Nao executa argumentos arbitrarios
  nem relanca browsers para tentar reconstruir trabalho que desconhece.

## Recuperacao unificada

O menu [8] lista backups Windows v2, preferencias graficas, caps e sessoes do usuario.
Cada schema usa seu adaptador com verificacoes de alvo, integridade/conflito e owner.
Journals desconhecidos sao recusados. Backup ilegivel aparece no catalogo de CLI
para inspecao; nao recebe um reset presumido. Recuperacao Windows requer elevacao.
Valores de fabrica nao substituem o estado anterior capturado.

Recuperar um backup e uma alteracao real: escolha o item correto pelo tipo, data e
caminho exibidos. Um restore de perfil MSAA8 anterior, por exemplo, retorna a8x.

## Testes e alcance

Fixtures sem modificar processos reais cobrem write-ahead, aplicacao/restauracao,
falha apos escrita, PID reutilizado, conflito externo, idempotencia e recusas de
nomes protegidos. Hub testa despacho por schema e recusas de owner/alvo/legados.
Preview local foi executado sem modificar prioridades. Nao houve ensaio de ganho
de FPS desta sessao nesta maquina. As regras de WHEA nao foram removidas.

Fonte: https://learn.microsoft.com/en-us/windows/win32/procthread/scheduling-priorities

## Modulos ainda pendentes

Migracao de IFEO/plano legado com proveniencia, novos perfis graficos suportados
por cada jogo e integracao de fabricantes continuam separados. Esta entrega nao
resolve gargalo de GPU, limita o ping da operadora ou certifica estabilidade de CO.
