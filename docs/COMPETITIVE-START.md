# Start Competitivo e Apps Lite (v2.5.0)

## O que foi analisado no PRACC

Inspeção local da versão 1.0.12.0, assinatura válida da stonefire GmbH, telas de configuração fornecidas pelo usuário e textos de ajuda do renderer instalado. Leitura do pacote para localizar a ajuda, sem executar/extrair o código do concorrente para o BNQQ, copiar algoritmos, contornar licença ou acessar credenciais. A automação de cliques retornou `SendInput` erro 87; não foi executado benchmark nem acionado um perfil do PRACC pela automação.

O texto de ajuda do ZEN descreve suspensão de processos e restauração de janelas/processos na saída. Isso é a descrição do fornecedor, não uma comprovação de quais processos são suspensos na máquina. A tela de setup sozinha não comprova que todas as opções estejam aplicadas.

| Função apresentada | Avaliação e decisão no BNQQ |
| --- | --- |
| Ajustes temporários com reversão | Útil como arquitetura. Reutilizamos nosso controlador com journal e identidade PID + início + usuário/sessão. |
| Afinidade/prioridade/boost/I/O agrupados | Não comprova ganho nem informa valores. Prioridade moderada em background é padrão; CPU Sets opcionais usam topologia real. Não transferimos configurações desconhecidas. |
| ZEN/suspensão de processos | Pode reduzir trabalho concorrente, mas pode congelar voz, compartilhamentos ou dependências. Sem suspensão/encerramento em massa e sem matar Explorer. |
| Limpeza de memória | Método não confirmado. Não purgamos standby nem esvaziamos working sets automaticamente durante partidas. |
| Energia | Só avaliar separadamente e com estabilidade; não faz parte do Start. |
| Serviços não essenciais | A lista não foi confirmada. Sem desligamento automático amplo, serviços Riot/anti-cheat ou áudio. |
| Efeitos visuais e overlays | Dependem do aplicativo e da implementação; não há ganho universal demonstrado. |
| Limpeza de temporários | Já disponível no menu 28, antes da partida. Não roda no loop competitivo. |

Não classificamos todo ajuste desconhecido como placebo: falta de evidência significa efeito não confirmado. Não foram medidos FPS, 1% low, 0.1% low ou mouse-tela com PRACC vs BNQQ.

## Menu 29: Start Competitivo

```powershell
.\bnqq.ps1 start-competitive -FrameProcess VALORANT-Win64-Shipping.exe
.\bnqq.ps1 start-competitive -StartAction run -FrameProcess VALORANT-Win64-Shipping.exe -LaunchGame
.\bnqq.ps1 start-competitive -StartAction run -FrameProcess cs2.exe -LaunchGame -KeepApps Discord,Spotify,msedge
.\bnqq.ps1 start-competitive -StartAction stop
.\bnqq.ps1 start-competitive -StartAction status
```

A prévia informa jogo aberto, participantes, apps preservados, atestado e controladores concorrentes. O comando pode usar um jogo já aberto ou iniciá-lo pelo Steam/Riot Client instalado e com assinatura validada. Não abre o executável do jogo diretamente nem substitui o fluxo de anti-cheat. Se a preparação estiver bloqueada, não lança o jogo para tentar contornar o bloqueio.

Por padrão, somente Edge, Chrome, Firefox e OneDrive são candidatos à redução temporária de prioridade, após atividade de CPU observada. Não aplica uma alteração fictícia a todos os programas só porque estão abertos. Discord, Spotify, Explorer e WebView são preservados; inclua qualquer navegador que esteja usando para vídeo/chamada em `-KeepApps` para excluí-lo da política também. Não há detecção automática confiável de chamadas/streams neste módulo.

O controlador Focus já existente amostra a cada 5 segundos, admite no máximo dois participantes por ciclo, verifica identidade e restaura ao usar Alt+Tab, na saída do jogo, em falha, timeout ou parada cooperativa. Pode selecionar processos elegíveis que abram depois. O ciclo registra sobrecarga de amostragem; não faz WMI por frame. Processos filhos podem herdar prioridade reduzida, e sem estado original conhecido não são promovidos artificialmente; reabra o aplicativo se necessário.

`-StartPolicy CpuSets -BackgroundCores 2` é opcional e reutiliza detecção de núcleos físicos e SMT. Aplica colocação de background somente aos candidatos permitidos. Não separa threads pares/ímpares, não altera afinidade do jogo e não isola Vanguard. CPUs híbridas/multigrupo podem ser recusadas por falta de política compatível. Veja [CPU Sets da Microsoft](https://learn.microsoft.com/en-us/windows/win32/procthread/cpu-sets).

## Um controlador por vez

PRACC, EXM e Process Lasso/ProcessGovernor detectados bloqueiam a nova sessão. Não são encerrados à força pelo BNQQ. O guard é rechecado no início e nos ciclos de saúde, aproximadamente a cada 10 segundos; não garante impedir toda corrida entre ferramentas. Se outro aparecer durante a sessão, o controlador sai restaurando o que possui. Também há bloqueio de outro controlador BNQQ já ativo.

O atestado HeavyQA recente do boot/configuração e as verificações de WHEA existentes continuam obrigatórios para controle de recursos. Uma boa experiência subjetiva em jogo não cria um atestado. O Start não roda HeavyQA automaticamente, não apaga logs e não relaxa as proteções. Em caso de crash do controlador, use os journals no menu de recuperação; restauração automática não é garantida após falha abrupta do processo/Windows.

## Menu 30: Apps Lite

```powershell
.\bnqq.ps1 app-lite
.\bnqq.ps1 app-lite -LiteAction apply -LiteApps Edge,Chrome
.\bnqq.ps1 app-lite -LiteAction restore -BackupFile 'JOURNAL_RETORNADO.json'
```

Preferências oficiais por usuário, com todos os originais salvos antes da primeira escrita:

| Aplicativo | Solicitação |
| --- | --- |
| Edge | Desabilitar Startup Boost e execução depois de fechar; habilitar suspensão de abas inativas após 5 minutos. |
| Chrome | Desabilitar execução em background após fechar a última janela. |
| Discord/Spotify | Preservar voz/música, sem alteração de prioridade/afinidade pelo Start. Não modificamos clientes com patches ou flags desconhecidas. |

Se uma política já estiver definida na máquina, o módulo informa o estado e não a sobrescreve. Não conta preferências já existentes como novos ganhos. Somente políticas listadas são gravadas em HKCU; não altera atualizadores, segurança, aceleração gráfica ou permissões. Políticas podem mostrar o navegador como gerenciado.

Leitura correta do registro prova a gravação, **não a aceitação pelo navegador**. Confirme em `edge://policy` ou `chrome://policy` quando puder abrir o navegador. A Microsoft documenta restrições para perfis Edge conectados a conta Microsoft. Não presumimos que a ausência de erro no PowerShell confirme aplicação no perfil.

A suspensão nativa de abas usa heurísticas para preservar atividades como áudio e vídeo; não é garantia para todo site. Fontes: [SleepingTabsEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/SleepingTabsEnabled), [SleepingTabsTimeout](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/SleepingTabsTimeout), [StartupBoostEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/startupboostenabled), [BackgroundModeEnabled do Chrome](https://chromeenterprise.google/intl/en_uk/policies/background-mode-enabled/).

Para deixar o Discord mais leve usando sua própria interface: ativar [movimento reduzido](https://support.discord.com/hc/en-us/articles/360040613412-Reduced-Motion-Setting) e desativar overlay/[Clips](https://support.discord.com/hc/en-us/articles/16861982215703-Clips) se não usa essas funções. Isso pode remover animações/captura dispensáveis; não garante melhora de FPS. Não desabilitamos aceleração globalmente: transferir renderização para CPU pode piorar o cenário. Não foi aplicada configuração interna do Discord por automação nesta entrega.

Backups em `%LOCALAPPDATA%/BNQQ/data/app-lite/GUID.json`, integrados ao menu de recuperação e Incident-Rollback. Reaplicação idêntica não sobrescreve o backup; conflitos externos são preservados; falha parcial tenta restaurar as outras políticas. Não exige reiniciar Windows, mas a aceitação/atualização de algumas preferências depende do navegador.

## Limites de desempenho e input

Esses mecanismos podem reduzir disputa por recursos quando há background concorrente. Não prometem FPS adicional em PC ocioso nem zero stutter/delay. São necessários cenários comparáveis para atribuir ganho de 1% low. Não há medição mouse-tela nem alteração de polling/DPI/teclado/USB neste módulo.

Não usamos prioridade Realtime/High para o jogo. A [Microsoft alerta que Realtime pode prejudicar mouse, teclado e tarefas essenciais](https://learn.microsoft.com/en-us/windows/win32/procthread/scheduling-priorities). O modo de background via `SetPriorityClass` é restrito ao próprio processo; não o aplicamos incorretamente a outros apps. [Referência da API](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setpriorityclass).
