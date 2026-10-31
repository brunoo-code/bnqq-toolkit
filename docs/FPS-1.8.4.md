# Motor competitivo 1.8.4: entrega e limites

## 1. Controle de carga: implementado para CS2

`framepacing` controla separadamente menu e partida. Por padrao preserva o cap da
partida (-1) e propoe 120 no menu. Alterar limite da partida e uma escolha explicita:
0 deixa sem teto; 60..1000 define teto. Nao existe cap universal para 240 Hz.
Um cap pode reduzir uso/filas e tambem reduzir FPS ou aumentar latencia; o resultado
depende do gargalo e da integracao Reflex. Nao e gerador de FPS.

```powershell
.\bnqq.ps1 framepacing -DryRun
.\bnqq.ps1 framepacing -CompetitiveAction apply -MenuCap 120
.\bnqq.ps1 framepacing -CompetitiveAction apply -GameCap 240 -MenuCap 120
.\bnqq.ps1 framepacing -CompetitiveAction restore -BackupFile JOURNAL
```

Feche CS2 normalmente antes da escrita. Descoberta Steam usa a mesma selecao segura
do perfil grafico; em varias contas use GameConfigDirectory. Somente fps_max e
fps_max_ui (incluindo variante $2) existentes podem mudar. Arquivo desconhecido ou
ambiguo e recusado. Preserva bytes externos, bindings e sensibilidade. Backup unico
anterior a escrita, hashes, substituicao atomica, restauracao exata/idempotente e
recusa de edicao externa. Nao integra backup de servicos/registro nem redefine Windows.
Estas preferencias de jogo nao liberam alteracoes de hardware bloqueadas por WHEA.

## 2. Criterio de qualidade: implementado

O comparador agora valida 1% e 0.1% lows finitos/positivos e impede classificacao
favoravel quando ha regressao media acima de 1% nesses lows ou acima de 1% no
jitter/frequencia de intervalos >16.667ms. Preserva separacao de p99 entre rodadas,
protecao de FPS medio e p99.9. Um baseline sem intervalos longos nao pode aceitar
novos intervalos longos como vantagem. Gates individuais sao exportados.

A margem de 1% e uma regra conservadora de engenharia, nao significancia estatistica.
O motor nao prova causalidade nem certifica input lag; exige contexto igual e 3+3
rodadas intercaladas. Nao relaxar esses criterios para fabricar resultado positivo.

## 3. Perfil grafico GPU: existente, expansao pendente

MSAA reversivel esta implementado. Nao baixar sombras por padrao: a visibilidade
de adversarios e parte da experiencia competitiva. Diminuir carga GPU pode ajudar
quando GPU limita; nao resolve gargalo CPU, compilacao ou interrupcoes. Proxima
expansao deve vincular escolhas visuais ao jogo/driver, preservando controles.

## 4. Concorrencia de programas: pendente

Projetar sessao de jogo com lista de aplicativos escolhida pelo usuario, fechamento
cooperativo, exclusao de apps com trabalho aberto e retomada controlada. Nao repetir
o antigo DeepFreeze: suspensao arbitraria e perda do estado em memoria nao sao
aceitaveis. Nao instalar watcher variavel no caminho de medicao de frametime.

## 5. Latencia de entrada e exibicao: parcial

Perfis pessoais guardam declaracoes, nao controlam firmware. Integracoes futuras
precisam de API/documentacao do fabricante e leitura de volta. Polling nominal,
distancias de actuation e FPS do sensor nao medem mouse/teclado-tela. Reflex deve
ser usado pelo jogo; nao ativar Ultra do driver esperando efeito adicional ao Reflex.
Nao impor fullscreen ou MPO off como cura universal; medir o modo de apresentacao.

## 6. Plataforma e migracao: pendente, governanca existente

Inventariar IFEO, plano de energia legado, drivers, overlays e servicos com origem
identificavel. Correcao seletiva requer estado previo e rollback. Nao restaurar
defaults imaginados. Cache de shaders nao deve ser limpo em loop. SMT, C-states,
HPET, TSC, standby purge e afinidade nao entram em preset universal. WHEA recente
continua bloqueando intervencoes de hardware/Windows. BIOS/PBO/RAM sao fora do
alcance desta atualizacao; dez minutos de HeavyQA nao certificam estabilidade.

## Fontes primarias

* Valve: https://help.steampowered.com/en/faqs/view/418E-7A04-B0DA-9032
* NVIDIA: https://www.nvidia.com/en-au/geforce/guides/system-latency-optimization-guide/
* NVIDIA: https://developer.nvidia.com/performance-rendering-tools/reflex

Publicado como funcionalidade e controle de qualidade. Nenhum percentual de ganho,
promessa de 99.9% de potencial ou superioridade de mercado foi demonstrado.
