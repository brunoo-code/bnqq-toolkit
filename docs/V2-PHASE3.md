# BNQQ 2.0.2 — fase 3: vetores 3, 5 e 6

## Memoria: margem real, sem purga

`memory` consulta `Kernel32.K32GetPerformanceInfo`, independente de strings SMBIOS/WMI. Exporta RAM disponivel, total fisico, commit usado/limite e cache do sistema. Disponivel inclui memoria standby reutilizavel; isso nao significa RAM desperdicada. Cache do sistema nao e contado como um processo a ser encerrado.

O guard desta fase recusa novos experimentos com menos de 512 MiB disponiveis ou menos de 1 GiB de margem de commit. Sao limites operacionais conservadores, nao diagnostico de stutter. Snapshot isolado nao mede paging sustentado, frequencia da RAM ou latencia de acesso.

Nao muda pagefile, memoria comprimida, privilegios de Lock Pages ou alocacoes do jogo. Dar privilegio de Large Pages nao transforma automaticamente as alocacoes de outro programa. Nao ha purga de standby, working set ou cache.

## NVMe: politica documentada do StorNVMe

Backend opcional confirma disco NVMe, controlador presente com servico `stornvme` e driver Microsoft em execucao. Fabricante/modelo da placa-mae nao autoriza mudancas. Se consultas falham ou o driver nao e confirmado, retorna Unsupported.

Aplica somente dois orcamentos AC=0 ms em SUB_DISK:

- `fc95af4d-40e7-4b6d-835a-56d131dbc80e`: tolerancia de transicao primaria.
- `dbc9e238-6de9-49e3-92cd-8c2b4946b472`: tolerancia de transicao secundaria.

DC e timeouts preservados. Sao parametros usados pelo StorNVMe na escolha de estados ociosos, nao um ajuste de latencia de leitura para zero. Podem elevar consumo/temperatura e nao garantem FPS. Nao alteram firmware, PCIe, MSI, APST diretamente ou buffers NTFS. A politica e do plano e pode afetar todos os controladores Microsoft StorNVMe que a utilizam.

No PC de desenvolvimento, ambos os valores AC ja eram zero: o backend retorna AlreadyConfigured e nao repete a gravacao. Quando ha diferenca, usa journal v2, verificacao de plano/valores, guard de memoria, administrador, HeavyQA/WHEA e rollback. A origem AC/DC e preservada no backup; a recuperacao nao depende de novo HeavyQA.

## Rede: checksums suportados, sem restart implicito

`nic` seleciona um adaptador fisico por nome exato ou o unico conectado. Interfaces virtuais sao excluidas. Identidade salva por GUID, PnP e versao do driver, sem mudar MAC, rotas, DNS ou portas.

Somente propriedades ja existentes e anunciando valor 3 (Rx/Tx) sao admitidas:

- `*IPChecksumOffloadIPv4`
- `*UDPChecksumOffloadIPv4`
- `*UDPChecksumOffloadIPv6`

Usa objeto CIM exato no setter, nomes escapados na consulta e `-NoRestart`. Nenhuma chave e criada. TCP checksum, LSO, RSS, interrupt moderation, EEE e buffers permanecem como estavam. O beneficio potencial e retirar calculo de checksum da CPU; nao encurta o caminho ate o servidor nem comprova menor ping ou melhor p99.

`stage` **salva configuracao, nao certifica ativacao em runtime**. Retorna `Staged`, `RequiresAdapterRestart=true` e `RuntimeActivation=NotAssumed`. A ativacao fica para um restart manual do adaptador ou boot apropriado; pode interromper a conexao. O toolkit nunca reinicia o adaptador automaticamente nesta fase. O getter de propriedades nao e tratado como prova de checksum calculado no hardware ou de throughput.

Journal `BNQQ.Nic.1` atomico antes de cada propriedade. Restaura valores exatos com NoRestart, verifica estado e recusa alteracao externa/driver diferente. A recuperacao da configuracao tambem pode exigir reativacao do adaptador para refletir em runtime. Alteracao de registro/configuracao e ativacao do miniport sao estados diferentes. O backup cobre os campos modificados, nao uma redefinicao de toda a rede.

Na Realtek 2.5GbE da maquina de desenvolvimento, os tres checksums estavam em 0 e o driver anunciava 0/1/2/3. RSS nao foi presumido nem criado. Isso gerou uma candidata de configuracao, sem afirmar ganho de FPS. A aplicacao real depende dos mesmos gates de estabilidade.

## Operacao e validacao

```powershell
.\bnqq.ps1 memory
.\bnqq.ps1 nvme -NvmeAction plan
.\bnqq.ps1 nvme -NvmeAction apply
.\bnqq.ps1 nic -NicAction plan
.\bnqq.ps1 nic -NicAction stage -AdapterName Ethernet
.\bnqq.ps1 nic -NicAction restore -BackupFile JOURNAL
.\scripts\Invoke-NightPhase3.ps1 -Apply
```

Menus 13 e 14. `-DryRun` forca previa. O runner nao pede elevacao ou reinicia dispositivos: salva resultados, registra falhas e verifica WHEA/Kernel-Power; so pode encaminhar o journal desta execucao ao Incident-Rollback. NIC foi adicionada ao catalogo de recuperacao.

Fixtures cobrem memoria nativa/pressao, capacidade StorNVMe, GUIDs/ranges, AC/DC, no-op, falha apos escrita, WHEA, identidades, valores externos, backups e recuperacao. O mock do cmdlet de rede verifica que cada gravacao usa NoRestart e objeto exato. Valores de rede e suporte NVMe foram lidos nativamente; nao foi forcada gravacao em hardware instavel para fabricar um resultado. Nao houve benchmark novo no jogo nem ganho de desempenho certificado.

Referencias: [memoria do kernel](https://learn.microsoft.com/en-us/windows/win32/api/psapi/nf-psapi-getperformanceinfo), [campos de memoria](https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-performance_information), [StorNVMe](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/power-management-for-storage-hardware-devices-nvme), [offloads](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/performance-in-network-adapters), [setter de propriedade](https://learn.microsoft.com/en-us/powershell/module/netadapter/set-netadapteradvancedproperty).
