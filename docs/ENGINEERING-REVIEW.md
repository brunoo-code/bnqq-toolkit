# Revisao de produto e decisao de engenharia

Revisao de documentacao publica dos fornecedores em 31/10/2026. Nao houve
compra, desbloqueio, descompilacao nem auditoria do codigo privado dos produtos.
Uma lista comercial nao demonstra melhoria neste PC; ausencia de prova publica
tambem nao prova, por si, que uma funcao nunca tenha efeito.

| Abordagem documentada | Decisao BNQQ |
|---|---|
| Bitsum ProBalance: reduzir temporariamente prioridade de processos concorrentes | Implementacao propria, opt-in, lista restrita, identidade/SID/sessao e journal; evoluir liberacao quando a carga termina. Sem copiar algoritmo ou afirmar equivalencia de beneficio. |
| Bitsum Performance Mode: trocar plano enquanto app roda | Suporte de energia existente continua opcional e sujeito a estabilidade. Nao usar readiness maxima como sinonimo de melhor frametime. |
| CPU Sets em CPUs hibridas/multiplos CCDs | Topologia nativa, sem inferir CCD por threads pares/impares. O 5700X declarado nao recebe receita de X3D com dois CCDs. |
| EXM: desabilitar C-States e fixar estados de processador | Nao aplicar automaticamente, especialmente com WHEA fatal. Maior consumo e transicoes diferentes nao constituem prova de ganho. |
| EXM: ajustes de DMA remapping/HDCP e configuracoes de GPU | Nao copiar chaves pelo nome. Exigir API documentada, suporte de driver e objetivo demonstravel; preservar seguranca. |
| EXM: agrupar svchost e remover tarefas/servicos amplamente | Nao adotar como pacote universal. Preferir leases de alvos especificos, sem encerrar processos. |
| EXM: ajustes AMD/NVIDIA/Intel diferentes | Identificar fornecedor/versao observados e disponibilidade real do backend. Nao converter parametros de um fabricante para outro. |
| LatencyMon: medir DPC/ISR, hard faults e timer | Medicao e atribuicao separadas do ajuste. O fabricante documenta que o proprio monitor pode influenciar DPC; nao confundir relatorio de audio com mouse-tela/FPS. |

## Diferencial que pode ser sustentado

O produto deve registrar o que detectou, por que escolheu uma acao, o estado
anterior, a verificacao da escrita e o resultado medido separadamente. Liberar
recursos quando a concorrencia termina; evitar reescrever configuracoes em loops.
Nenhum numero de tweaks, preco premium ou perfil extreme substitui essa cadeia.
Ainda nao ha evidencia para declarar o BNQQ superior ao mercado em FPS/latencia.

## Plataforma (2.0.8)

`timers`, `usb-topology` e `security` sao consultas somente leitura. O BCD e
enumerado, nunca alterado; valores localizados sao preservados sem adivinhar
booleanos. Ausencia de flag nao identifica o clock efetivo. HPET PnP nao e QPC.
USB segue DEVPKEY_Device_Parent com cache (128 consultas, 12 ancestrais, 32
interfaces Mouse/Keyboard), reconhece servico de controlador USB e interrompe
ciclos. Interfaces logicas nao equivalem a perifericos fisicos nem polling rate.
VBS/HVCI sao observados via Win32_DeviceGuard; falhas ficam Unknown.

WHEA 18 das ultimas 72h passa a bloquear tambem o caminho de recursos entre
boots. Reiniciar ou obter PASS curto nao deve apagar esse sinal de instabilidade.
O gate nao e um diagnostico de qual componente/configuracao provocou a falha.

## Fontes primarias

- [Bitsum: ProBalance](https://bitsum.com/apps/process-lasso/docs/algorithms/probalance/)
- [Bitsum: guia de configuracao](https://bitsum.com/apps/process-lasso/docs/getting-started/setup-guide/)
- [EXM: lista recomendada](https://support.exmtweaks.com/en/our-recommended-optimizations)
- [LatencyMon: limites tecnicos](https://resplendence.com/latencymon_technical)
- [Microsoft: BCDEdit /set](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--set)
- [Microsoft: Get-PnpDeviceProperty](https://learn.microsoft.com/en-us/powershell/module/pnpdevice/get-pnpdeviceproperty)
- [Microsoft: memory integrity/DeviceGuard](https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity)
