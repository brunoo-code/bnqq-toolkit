# BNQQ 2.0.1 — fase 2: vetores 2, 13 e 18

## Driver NVIDIA: perfil existente por jogo

O backend usa NVAPI do driver instalado: consulta placa, versao, perfil, executaveis associados, origem do valor e valores anunciados. Verifica assinatura da biblioteca no System32 e registra SHA-256. Nao distribui DLL de driver, Profile Inspector ou codigo do EXM. Metadados de interface seguem o SDK NVIDIA na revisao indicada em `lib/NVIDIA-NOTICE.txt`.

O unico ajuste gravavel e `PREFERRED_PSTATE_ID=1`, o modo de energia Prefer maximum performance, em perfil ja existente de CS2 ou Valorant. Preserva configuracao global, Reflex, filas de render, qualidade grafica e arquivos do jogo. Nao e overclock nem garantia de clocks fixos, FPS ou latencia.

Antes de gravar, exige caminho local do executavel, um GPU NVIDIA confirmado, setting existente, valor suportado, escopo de aplicativos conhecido, jogos/editores de perfil fechados, administrador, HeavyQA e ausencia de WHEA recente. Perfil compartilhado fora da familia do jogo e recusado. Nao recria perfil: isso poderia perder compatibilidades predefinidas do driver.

Quando o valor efetivo ja e 1, retorna `AlreadyMaxPerformance`, mesmo que herdado da configuracao global. Nao cria um override equivalente e nao exige stress para uma operacao sem alteracao.

O publico consulta os adaptadores observados e tenta confirmar a disponibilidade pelo driver NVIDIA real. AMD/Intel sem esse backend recebem indisponivel/nao suportado, sem preset NVIDIA ou arquitetura inventada por WMI. Multiplos GPUs NVIDIA sao listados, mas a aplicacao conservadora desta versao exige um unico GPU.

## Backup e recuperacao

Journal `BNQQ.Nvidia.1` salvo atomicamente antes da gravacao, com identidade do perfil, associacoes, driver/biblioteca, valor e existencia de override local. A aplicacao revalida o alvo e confere o resultado. Erro de gravacao ou novo problema de saude provoca tentativa de restauracao; falha fica em `NeedsRecovery` e no log noturno.

Rollback restaura o valor local original ou remove somente o override criado. Se o valor anterior era herdado, nao cria um novo override para simular a heranca. Preserva mudancas globais externas legitimas. Driver/biblioteca/associacoes diferentes ou outro valor local inesperado bloqueiam restauracao automatica. Catalogo e Incident-Rollback incluem o novo tipo.

Nao existe CAS entre ferramentas diferentes na API DRS. Feche editores e evite outros programas alterando perfis ao mesmo tempo; a trava BNQQ nao coordena software externo. Reversao modifica a configuracao persistida: programas ja abertos podem precisar ser reabertos para consumir o perfil. O toolkit nao encerra jogos ou trabalho salvo/nao salvo. Nao e reset integral da base de perfis nem promessa de restauracao instantanea apos BSOD.

## Shader cache: preservar, sem chave fantasma

`gpu-cache` consulta o limite do cache pelo driver e registra se a antiga chave de ativacao foi encontrada. Uma chave legada ausente nao e tratada como cache desativado. Nenhuma chave antiga e criada e nenhum arquivo de cache e apagado automaticamente. O valor de capacidade e exportado cru; nao e taxa de cache hit nem medicao de compilacao.

No PC usado no desenvolvimento: ambos os jogos ja herdavam modo de energia 1; o limite de cache consultado era 10240; a antiga chave de ativacao nao foi encontrada no driver 621.01. Portanto nao houve novo ajuste nesses pontos. A limpeza antes de cada jogo foi rejeitada porque descarta trabalho de compilacao reutilizavel.

## FrameBench com sensores nativos

`-GpuTelemetry` inicia coleta opcional em thread do proprio toolkit: uso da GPU, clocks, temperatura e P-state, com intervalo solicitado de 500 ms e no maximo 610 amostras. Usa a biblioteca instalada, sem processo nvidia-smi por amostra. O worker tem prazo e sinal de parada; a captura tenta encerra-lo em `finally`, inclusive se PresentMon falhar. Nao usa Thread.Abort nem descarrega a biblioteca enquanto uma chamada do worker ainda esta em curso.

Dados brutos e status sao incluidos no result.json. O contexto registra modo, intervalo e hash da biblioteca: A/B exige a mesma instrumentacao. Comparadores recusam falha, dados nao finitos, gaps maiores que dois segundos e cobertura inferior a 80% da duracao util. Capturas antigas sem instrumentacao continuam validas sob os criterios anteriores. `-Effective` legado e hotkey nao recebem esse modo novo; faca novas capturas temporizadas A/B.

Sensores sao do dispositivo inteiro, nao exclusivos do jogo. Nao sao GPU busy por frame, latencia de input ou prova da causa de um stutter. O relogio de amostras e seus UTCs sao exportados; nao se assume alinhamento exato com a origem de tempo de todo CSV PresentMon. O overhead ainda nao foi quantificado no jogo: a coleta e opt-in e precisa estar igual em ambas as variantes.

```powershell
.\bnqq.ps1 gpu -GpuAction status
.\bnqq.ps1 gpu -GpuAction plan -FrameProcess cs2.exe
.\bnqq.ps1 gpu -GpuAction apply -FrameProcess cs2.exe
.\bnqq.ps1 gpu-cache
.\bnqq.ps1 gpu -GpuAction restore -BackupFile JOURNAL
.\bnqq.ps1 framebench -FrameSeconds 60 -FrameSkip 5 -Scenario prefire -SettingsHash cena-fixa -ExperimentId gpu-01 -Variant baseline -GpuTelemetry
.\scripts\Invoke-NightPhase2.ps1 -Apply
```

O menu 12 expoe o backend do driver. Caminhos nao encontrados exigem `-GameExecutable` em instalacoes fora das fontes reconhecidas. O runner noturno salva resultados por jogo e verifica saude antes da publicacao; somente journal da execucao atual pode ser revertido por ele. Nenhum reboot, encerramento de processo ou elevacao automatica.

## Validacao desta fase

Fixtures cobrem aplicacao/recuperacao, falha apos save, WHEA, conflitos, valores herdados/explicitos, fornecedor, escopo, permissao, no-op e limpeza do coletor quando a captura falha. A ponte C# e compilada no CI.

No RTX 2060 real, NVAPI confirmou GPU/driver/perfis, aceitou criacao/remocao de override em sessao **sem chamar Save**, e uma sessao nova confirmou que o estado persistido permaneceu igual. A coleta de sensores tambem foi executada nativamente. A gravacao persistente e suas falhas foram exercitadas por fixtures; nao foi forcada no PC porque o ajuste ja estava ativo. Nenhum ganho de FPS/p99 foi medido e nao ha certificacao FACEIT/Vanguard.

Referencias: [SDK NVAPI](https://github.com/NVIDIA/nvapi), [NVAPI DRS](https://docs.nvidia.com/nvapi/group__drsapi.html), [controles NVIDIA](https://www.nvidia.com/content/Control-Panel-Help/vLatest/en-us/mergedProjects/3D%20Settings/Manage_3D_Settings_(reference).htm).
