# Drivers e interrupcoes — 2.0.7

`drivers` e um inventario somente leitura de fontes CIM locais, com timeout de
operacao de cinco segundos e ate 4096 registros por fonte. Reune dispositivos,
pacotes de driver e servicos de kernel por identificadores exatos. Mostra todas
as correspondencias quando ha ambiguidade, em vez de escolher uma versao.
Dados ausentes continuam ausentes; falha de uma fonte nao elimina as outras.
Nao usa identificacao SMBIOS da placa-mae para decidir ajustes.

IsSigned e uma observacao do provedor, nao validacao Authenticode do arquivo
carregado. Codigo de problema do dispositivo nao prova causa de DPC/stutter.
Idade, fabricante e presenca de um driver nao geram recomendacao de desativacao.
O inventario pode conter identificadores pessoais: salve localmente, sem publica-lo.

## Analise offline DPC/ISR

`dpc` sem arquivos apresenta o contrato de importacao. Com DpcCsv e DpcMetadata,
analisa eventos individuais ja normalizados. Nao importa ETL diretamente nem
aceita qualquer export do WPA automaticamente. Esta etapa nao inclui gravador
ETW ou conversor automatico de WPA. Nao faz captura, instala ferramenta ou altera
IRQs, dispositivos, drivers, MSI, timers ou configuracoes do jogo.

CSV UTF-8 separado por virgulas, sem agregacao, com cinco colunas:

| Coluna | Conteudo |
|---|---|
| StartSeconds | Inicio relativo do evento, em segundos QPC normalizados |
| DurationUs | Duracao inclusiva de parede em microssegundos, positiva |
| CpuIndex | Indice global achatado da CPU capturada, de 0 ate LogicalProcessorCount-1 |
| Module | Nome simples .sys/.exe ou [unknown]; sem caminhos ou comandos |
| Kind | DPC ou ISR |

JSON separado obrigatorio:

```json
{
  "Schema": "BNQQ.DpcCsv.1",
  "Aggregation": "IndividualEvents",
  "TimestampUnit": "seconds",
  "DurationUnit": "microseconds",
  "DurationSemantics": "InclusiveWallTime",
  "Clock": "QPC",
  "CsvSha256": "SHA256_REAL_DO_CSV",
  "LostEvents": 0,
  "LogicalProcessorCount": 16,
  "WindowStartSeconds": 0,
  "WindowDurationSeconds": 60
}
```

O exemplo de 16 CPUs nao e um preset: exige a quantidade do trace original.
Nao preencher LostEvents com zero por suposicao. O analisador exige zero
declarado, mas nao verifica essa declaracao contra o ETL de origem. Hashes
identificam os arquivos analisados, sem autenticar a procedencia da coleta.
Unidades, relogio ou semantica desconhecidos exigem conversao verificada antes
da importacao. Duplicatas exatas sao recusadas para evitar exportacoes sobrepostas.

## O que o relatorio mede

Contagem, eventos/segundo e soma de duracoes por modulo/tipo; maximo e p99
nearest-rank das duracoes completas. Eventos cortados pela janela participam
da cobertura, mas ficam fora dos percentis para nao inventar caudas curtas.
A quantidade de eventos completos acompanha cada percentil.

Intervalos sobrepostos ou aninhados sao unidos por CPU antes de calcular a
cobertura. CPUs simultaneas sao normalizadas pela quantidade declarada de CPUs
e pela duracao da janela. A soma das duracoes por modulo pode se sobrepor e nao
e tempo exclusivo. A cobertura descreve somente os intervalos presentes na entrada;
nao certifica completude do trace nem atraso mouse-tela ou tempo em fila de DPC.

Modulos de infraestrutura como ndis.sys, wdf01000.sys, dxgkrnl.sys, storport.sys
e ntoskrnl.exe recebem indicacao de que precisam de stack/atribuicao adicional.
Mesmo um modulo especifico observado nao e automaticamente causa raiz. Sem trace
sincronizado, nao ha correlacao temporal com os frames do jogo.

Limites: CSV 16 MiB, metadata 32 KiB, 100000 eventos, janela de 1 a 300 segundos
em trace de ate sete dias. Arquivos alterados durante a leitura sao recusados.
Entrada vazia/invalida nao e interpretada como latencia zero.

## Fontes

- [Microsoft: CPU Analysis](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/cpu-analysis)
- [Microsoft: Measuring DPC/ISR Time](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/example-15--measuring-dpc-isr-time)
- [Microsoft: Win32_PnPSignedDriver](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/whqlprov/win32-pnpsigneddriver)

Testes desta etapa usam entradas pequenas simuladas. Nenhuma melhoria de FPS,
ping ou estabilidade foi demonstrada pelo inventario/analisador.
