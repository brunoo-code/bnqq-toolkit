# Sessao de upload — BNQQ 1.8.7

Funcao operacional para reduzir concorrencia de **upload** de aplicativos de sincronizacao enquanto CS2 ou Valorant esta aberto. Usa QoS nativo do Windows, sem alterar arquivos dos jogos, driver, BIOS, afinidade ou roteador. Funciona independentemente de GPU NVIDIA, AMD ou Intel; depende da disponibilidade do modulo NetQos, das permissoes e das politicas do Windows.

## Comportamento

- Apenas OneDrive.exe, Dropbox.exe e GoogleDriveFS.exe, explicitamente escolhidos. Lista vazia nunca cria uma regra global.
- `UploadKbps` usa **kbit/s decimais**: 512 significa 512.000 bits/s (64.000 bytes/s). E o limite solicitado em cada politica, nao um teto global compartilhado entre todos os programas ou fluxos.
- Nomes unicos, sem substituir politicas existentes. Recusa regras potencialmente sobrepostas; preserva regras especificas de outros executaveis, inclusive jogos.
- Politicas em `ActiveStore`: temporarias, nao persistem apos reinicializacao. Nao instala tarefas ou servicos.
- Aguarda a identidade da instancia original do jogo, verificando a cada dois segundos. Ao sair, remove apenas suas proprias politicas, conferindo todos os seletores e acoes relevantes.
- Journal atomico antes de cada criacao; recupera inclusive falha entre a criacao e sua verificacao. Se alguem alterar uma politica, recusa sobrescrever/remover essa alteracao e registra pendencia.
- Se fechar a janela a forca ou faltar energia, a remocao imediata nao e garantida: use **Recuperacao**, ou a politica temporaria desaparecera no proximo boot. Nao e necessario reiniciar numa saida normal.

## Uso

Menu **10 — Sessao de upload**, com escolha de apps, limite e jogo aberto. Mantenha a janela da sessao aberta enquanto joga. A sessao de prioridades e a de rede compartilham a trava de estado: nesta versao, execute uma por vez.

```powershell
# Previa: nenhuma politica criada, nenhuma permissao administrativa necessaria.
.\bnqq.ps1 net-session -NetworkApps OneDrive.exe -UploadKbps 512

# Aplicacao explicita; administrador, jogo aberto e governanca de estabilidade exigidos.
.\bnqq.ps1 net-session -NetworkAction run -NetworkApps OneDrive.exe -UploadKbps 512 -FrameProcess cs2.exe

# Recuperacao continua disponivel sem novo HeavyQA.
.\bnqq.ps1 net-session -NetworkAction restore -BackupFile CAMINHO_DO_JOURNAL
```

`-DryRun` sempre transforma a operacao em previa, inclusive quando combinado com `run` ou `restore`. O catalogo de recuperacao inclui `network-sessions`.

## O que este recurso pode entregar

Pode ajudar quando os uploads selecionados enchem a fila de saida e prejudicam o jogo. Se nao ha concorrencia, nao presumir beneficio. Nao reduz distancia ao servidor, nao limita downloads e nao controla outros aparelhos. Nao promete ganho de FPS, latencia mouse-tela ou um valor de ping. O alcance agregado do limite depende da classificacao de trafego e dos fluxos: nao tratar o valor configurado como medicao de throughput.

O Windows classifica o trafego por endpoint; nao assumir efeito retroativo imediato em conexoes ja estabelecidas. Inicie a sessao antes de uma nova transferencia de teste. O BNQQ nao fecha programas para forcar reconexao. Sem medir transferencia real, o retorno registra `TrafficMeasured=false`.

## Validacao

`tests/NetworkSession.ps1` cobre ciclo completo, falha depois da escrita, conflitos externos, journal adulterado, preservacao de outras politicas, ausencia de politica apos reboot, unidades, lista de apps e recusa administrativa/HeavyQA. Esses testes usam um adaptador em memoria e nao alteram o Windows do CI.

No desenvolvimento, tambem foi executado um teste nativo elevado de criacao/leitura/remocao para executavel ficticio, sem gerar trafego. A normalizacao dos nomes e os valores de todos os seletores/acoes foram confrontados com o provider real. Isso valida a integracao de politicas; **nao** constitui prova de reducao de ping ou verificacao de throughput limitado.

Referencias: [New-NetQosPolicy](https://learn.microsoft.com/en-us/powershell/module/netqos/new-netqospolicy), [remocao seletiva](https://learn.microsoft.com/en-us/powershell/module/netqos/remove-netqospolicy), [classificacao por endpoint](https://learn.microsoft.com/en-us/windows-server/networking/technologies/qos/qos-policy-works).
