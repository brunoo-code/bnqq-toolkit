# Migracao seletiva de IFEO 1.8.6

O comando `legacy` importa apenas a intencao de recuperar ausencia de seis valores
conhecidos: CpuPriorityClass, IoPriority e PagePriority nos PerfOptions de cs2.exe e
VALORANT-Win64-Shipping.exe. Nenhum outro valor, executavel, servico ou plano de
energia pode ser alterado por esse modulo.

## Fontes e escopo

Escolha explicitamente snapshots BNQQ antigos com Created e Entries. Por alvo,
o mais antigo dos arquivos selecionados determina o estado previo conhecido.
Isso nao prova que seja o primeiro backup real nem a configuracao de fabrica.
Timestamp e SHA256 nao autenticam o autor, a maquina ou completude da cadeia.
Nao use arquivos de terceiros como prova do estado anterior do seu Windows.

O importador exige Existed=false booleano, Kind/Value nulos e valor atual DWORD
igual ao antigo padrao aplicado pelo BNQQ (CPU3, IO3, Page5). Se o original ja
existia, nao tenta adivinhar como restaura-lo. Valor atual divergente ou original
invalido bloqueia toda a aplicacao. Datas futuras, entradas duplicadas e historico
contraditorio no mesmo timestamp sao recusados. Limites:64 arquivos,2MB por arquivo,
20000 entradas por snapshot. Caminhos legados com barras duplicadas sao normalizados
somente para comparacao com a lista fixa; nunca executados como comandos.

```powershell
.\bnqq.ps1 legacy -LegacyFiles A.json,B.json -DryRun
.\bnqq.ps1 legacy -LegacyAction apply -LegacyFiles A.json,B.json
.\bnqq.ps1 recover -BackupFile JOURNAL_DA_MIGRACAO
```

O exemplo nao seleciona automaticamente backups. Revise o plano por alvo e a
procedencia dos arquivos. Sem fontes, o comando recusa a operacao.

## Escrita e reversao

Aplicar exige administrador, governanca WHEA/HeavyQA valida para o codigo atual e
nenhum journal Windows pendente. Migracao anterior nao desfeita/recuperada bloqueia
nova aplicacao. Nao existe flag para contornar WHEA.

Antes de remover cada valor, o modulo grava seu estado atual exato em um novo
journal, verifica hash do snapshot de origem e detecta alteracao externa do
registro. O hash e calculado sobre os mesmos bytes que foram analisados.
Apenas o valor e removido: chaves nao sao apagadas, pois os backups antigos nao
registravam sua existencia original. Estado depois da escrita e verificado.

Em erro, tenta desfazer somente o que escreveu. Se houver conflito externo, nao
sobrescreve; o journal fica com NeedsRecovery. Recovery pode ser chamado elevado
sem QA aprovado, pois desfaz esta migracao. Isso recoloca os overrides anteriores
(por exemplo CPU3), nao e uma segunda limpeza. O menu8 reconhece esse schema.

Os overrides afetam criacao de processos. Nao altera prioridades de jogos ja
abertos, nao mata/reinicia jogos e nao exige reiniciar Windows. Nao ha promessa
de FPS maior: retirar prioridade forçada muda politica, com efeito a verificar.

## O que nao foi feito

Nao reconstrói backups sem proveniencia, nao migra arquivos .reg arbitrarios,
nao limpa IFEO inteiramente (Debugger e outras opcoes ficam intactos), nao reseta
servicos ou registro, nao remove planos de energia nem muda clocks/firmware.
Snapshots privados e planos com caminhos locais nunca entram no pacote publico.

Testes exercitam ordem das fontes, escopo, original ausente, rejeicao de flags
string, conflito atual, QA bloqueado, write-ahead, undo idempotente, falha apos
remocao e journal adulterado. Nao modificam registro real.

O menu9 oferece selecao de pasta de backups e exibicao do plano antes da aplicacao. Menu com -DryRun nao entra em fluxo interativo de escrita.
