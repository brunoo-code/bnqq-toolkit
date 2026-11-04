# BNQQ Competitive (v2.6.0)

Dois executáveis com finalidades separadas:

| Executável | Uso |
| --- | --- |
| BNQQ_Optimizer.exe | Configuração inicial, manutenção, relatórios, HeavyQA e recuperação. Alterações persistentes continuam explícitas. |
| BNQQ_Competitive.exe | Abrir antes de jogar, ou com o jogo aberto, para usar a sessão temporária sem navegar pelo menu completo. |

O Competitive possui entrada própria (`bnqq-competitive.ps1`) e carrega apenas os módulos necessários à sessão. O pacote ainda inclui as dependências e fontes usadas pela validação de integridade/prontidão; não é um cliente alternativo do jogo. Reutiliza o mesmo backend, limites, proteção de identidade e recuperação do BNQQ, sem criar um segundo controlador concorrente.

## Uso diário

1. Abra `BNQQ_Competitive.exe`.
2. Se houver apenas CS2 ou Valorant aberto, ele seleciona esse jogo. Se nenhum estiver aberto, ou ambos estiverem, oferece somente os dois jogos e cancelar.
3. Com os gates aprovados, usa o jogo aberto ou inicia pelo Steam/Riot Client assinado. Não executa HeavyQA, limpeza ou ajustes permanentes ao entrar.
4. Volte ao jogo: o controlador observa atividade nos apps de background permitidos e faz apenas os ajustes elegíveis.
5. Para desativar, use Alt+Tab para o console e pressione **Q** ou **Esc**. O jogo continua aberto e os ajustes temporários são restaurados ao estado anterior capturado.

Alt+Tab já pausa/restaura o período de foco; voltar ao jogo retoma a observação. Q/Esc encerra a sessão inteira. O teclado é consultado somente pelo buffer do próprio console, sem hook global ou interceptação das teclas do jogo. O ciclo verifica parada aproximadamente a cada segundo. Prefira Q/Esc a fechar a janela à força: falhas abruptas podem exigir os journals de recuperação no Optimizer.

O console mostra foco/pausa, participantes registrados e mudanças acumuladas. Zero participantes significa que nenhuma alteração foi necessária naquele período; não mostramos “100% otimizado”. A contagem registrada pode incluir um processo que encerrou antes da próxima restauração, não é medição de processos vivos nem de FPS.

Limite padrão de sessão: 240 minutos. Na saída normal, um relatório com os dados do controlador fica em `%LOCALAPPDATA%/BNQQ/data/competitive-reports`. Não há cálculo inventado de ganho de FPS/1% low ou medição de mouse-tela.

## O que ele faz e preserva

O padrão é reduzir temporariamente a prioridade de navegadores e OneDrive elegíveis após atividade de CPU medida, somente com o jogo em foco. Discord, Spotify, shell/Explorer, WebView, serviços, anti-cheat, jogo e periféricos ficam fora dessa política. Não usa purga de memória, Realtime, afinidade fixa do jogo, desligamento de serviços ou alteração de clocks/energia.

Requisitos de HeavyQA no boot/configuração atual, histórico WHEA, journals pendentes e ausência de outro otimizador continuam obrigatórios. O Competitive não cria certificado nem remove bloqueios. Uma mudança no backend crítico ou um reboot pode exigir nova validação. Isso não equivale a estabilidade absoluta ou garantia de desempenho.

## Atalhos e linha de comando

```powershell
.\BNQQ_Competitive.exe -FrameProcess VALORANT-Win64-Shipping.exe
.\BNQQ_Competitive.exe -FrameProcess cs2.exe -KeepApps Discord,Spotify,msedge
.\BNQQ_Competitive.exe -StopSession
.\BNQQ_Competitive.exe -DryRun
```

Os parâmetros são os da entrada dedicada: `FrameProcess`, `KeepApps`, `SessionMinutes`, `DryRun` e `StopSession`. Não oferece os comandos de manutenção do Optimizer. `StopSession` também sinaliza cancelamento durante a espera de abertura do jogo; não encerra o jogo que já iniciou.

O Competitive usa manifesto `asInvoker`, sem exigir administrador por padrão. O Optimizer continua com `requireAdministrator`. Os ajustes de prioridade são limitados ao próprio usuário/sessão; acesso negado é tratado com recusa, não elevação automática ou tentativa de tomar posse. Ambientes que restrinjam leitura dos logs podem impedir a prontidão.

## Build e testes

```powershell
.\build.ps1 -KeepBuild
.\tests\Launcher.ps1
.\build-competitive.ps1 -KeepBuild
.\tests\Launcher.ps1 -Exe .\dist\BNQQ_Competitive.exe -ExpectedEntry bnqq-competitive.ps1
```

Cada build atualiza a pasta de staging. Verifique o executável contra seu próprio payload imediatamente após compilá-lo. Os testes verificam entrada correta, manifesto de hashes, extração, rejeição de adulteração e argumentos sem executar Main/UAC. Fixtures de controle verificam tecla de parada, restauração, Alt+Tab, foco e descarte de handles. A prévia da entrada real não inicia jogos nem altera processos.

Os dois EXEs ficam na raiz e em `dist` nas entregas locais. Nenhum ganho de 1% low foi comprovado apenas por separar o executável: o benefício é simplificar o uso e aplicar de forma observável a política já existente quando há disputa por recursos.
