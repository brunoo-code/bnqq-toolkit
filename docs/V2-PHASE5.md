# v2.0.4 - aplicar com criterios proporcionais (vetores 6, 18, 19 e 20)

## Problema corrigido

O toolkit usava a mesma trava de WHEA de 72h para energia e para qualquer controle
de aplicativos. Alem disso, adicionar qualquer arquivo em lib invalidava o teste
de hardware, criando um ciclo de desenvolvimento sem chegar a aplicacao.

Agora existem duas admissoes, ambas exigindo teste real e recente:

- **Energia/clocks:** regra anterior de 72h sem WHEA, codigo completo e configuracao
  correspondentes. Unpark explicito, deep-idle e perfis de energia GPU/NVMe continuam
  nesse caminho. Nao ha flag de force para ignorar os erros.
- **Recursos reversiveis:** prioridades de background, CPU Sets sem Unpark, sessao
  Focus, QoS de apps e checksums suportados exigem HeavyQA schema 3, 10 minutos em
  todas as threads, I/O verificado, cauda idle de 30s, nenhum WHEA neste boot e
  nenhum WHEA/Kernel-Power 41 durante o teste. O boot, CPU, GPU/driver, RAM, energia
  e a implementacao critica do teste devem corresponder. Historico anterior permanece
  no Event Viewer; nao e apagado nem apresentado como resolvido.

O hash de recursos inclui Core.ps1, Governance.ps1, HeavyQA.ps1 e StabilityLoad.cs.
Alterar essas bases invalida o atestado, assim como reiniciar, mudar hardware/driver
GPU ou a energia observada. Um novo modulo de relatorio, por si so, nao altera a
evidencia de hardware. A validade continua sendo de 24h. Schema 2 nao libera recursos
pelo caminho novo. Nenhum certificado e migrado para PASS automaticamente.

O resultado schema 3 separa ResourceFingerprint de Fingerprint e informa
StrictConfigurationVerified. Se outros modulos mudarem durante a carga, o teste
pode verificar o contexto de recursos e recusar o contexto estrito. Qualquer mudanca
de hardware/energia ou da implementacao critica durante a carga reprova o teste.
Isso nao certifica estabilidade absoluta nem verifica todos os ajustes de BIOS/CO.

`readiness` mostra boot, quantidade de WHEA historica e deste boot, e as duas permissoes.

## Rede: configuracao salva versus carregada

`nic -NicAction stage` continua sem interromper a rede. `activate -BackupFile ...`
e uma acao separada e explicita: confere o backup, proprietario, GUID/PnP/driver e
valores atuais; salva a intencao antes do reset; reinicia somente o adaptador admitido;
aguarda link e rotas padrao e consulta os checksums IP/UDP expostos pelo driver.

O primeiro activate de um journal Staged reinicia o adaptador mesmo se o provider CIM
ja espelhar os valores salvos no registro. Esse espelho nao prova que o miniport
recarregou a configuracao. Chamadas seguintes sobre Activated verificado sao idempotentes.

`restore-active` restaura os valores originais e, quando necessario, reinicia o mesmo
adaptador para carrega-los. Restauracao nao exige novo teste de carga. O fluxo de
ativacao reverte valores e tenta recarregar o original se reset/verificacao/saude falhar.
Driver substituido ou propriedades alteradas por terceiros geram conflito, sem
sobrescrita. Nao ligar adaptador desabilitado, nao escrever rotas/IP/DNS e nao criar
propriedades ausentes. A espera por retorno e limitada a 30s por tentativa.

**O reset interrompe a conexao temporariamente.** E opt-in no produto publico. Nao
reinicia o computador e nao instala driver. O journal e a recuperacao sao mantidos.
Estado informado pelo driver nao prova que todo pacote foi processado pelo hardware,
nem comprova reducao de ping, maior FPS ou melhor p99.

## CLI

```powershell
.\bnqq.ps1 readiness
.\bnqq.ps1 nic -NicAction plan
.\bnqq.ps1 nic -NicAction stage
.\bnqq.ps1 nic -NicAction activate -BackupFile CAMINHO_DO_JOURNAL
.\bnqq.ps1 nic -NicAction restore-active -BackupFile CAMINHO_DO_JOURNAL
```

## Testes e limites do resultado

GovernanceScopes cobre eventos anteriores versus atuais, schema legado, boot novo,
hash de hardware/teste, validade temporal, proprietario e separacao de permissoes.
NicActivation usa adaptadores simulados para testar registro versus runtime, provider
espelhado, primeiro reset obrigatorio, idempotencia, restore com reset, falha parcial,
WHEA, driver diferente, estado externo, adaptador desabilitado e autoridade.

Na maquina do desenvolvedor o teste antigo terminara antes do ultimo boot. WHEA de
29/10 continuava bloqueando o caminho estrito; nao havia WHEA no boot de 31/10 durante
a inspecao. Esses fatos motivaram um novo teste, nao a exclusao de registros. Os perfis
de GPU/NVMe e a desativacao de gravacao ja estavam nos estados propostos; reaplica-los
nao seria um ganho novo. Capturas com mapa, polling ou afinidade diferentes nao
estabelecem melhora causal. A melhora de FPS continua dependendo de A/B comparavel.

Fontes primarias: [LastBootUpTime](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem),
[Set-NetAdapterAdvancedProperty/NoRestart](https://learn.microsoft.com/en-us/powershell/module/netadapter/set-netadapteradvancedproperty),
[Restart-NetAdapter](https://learn.microsoft.com/en-us/powershell/module/netadapter/restart-netadapter),
[Get-NetAdapterChecksumOffload](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapterchecksumoffload).
