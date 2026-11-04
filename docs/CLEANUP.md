# Limpeza conservadora (v2.4.0)

Menu 28 ou comando `cleanup`. A prévia é o padrão; aplicar exige ação explícita.

```powershell
.\bnqq.ps1 cleanup
.\bnqq.ps1 cleanup -CleanupAction apply
.\bnqq.ps1 cleanup -CleanupAction apply -EmptyRecycleBin
.\bnqq.ps1 cleanup -CleanupAction plan -CleanupAgeDays 7
```

Limpa arquivos das pastas temporárias padrão do usuário atual e do Windows com última modificação há mais de 48 horas. Não aceita caminhos arbitrários por parâmetro nem usa TEMP/TMP como raiz de exclusão. Pode aumentar a idade mínima de 2 até 90 dias. Não remove diretórios.

Preserva arquivos recentes, somente leitura, abertos por outros processos, dumps de falha, links e caminhos contendo cache, shader, Riot, VALORANT, Vanguard, Steam, BNQQ, Codex, Office, Outlook, unsaved ou recovery. Preserva a pasta de trabalho atual quando estiver em temporários. Não limpa Downloads, documentos, Prefetch, WinSxS, Windows Installer, logs de eventos ou caches de shaders. Não fecha programas, interrompe serviços, descarrega RAM, altera jogos ou promete ganho de FPS.

O scanner limita a visita a 50 mil entradas, 8192 diretórios ou aproximadamente 20 segundos, informando truncamento e falhas de acesso. Arquivos inacessíveis/em uso são ignorados; não assume privilégios nem força desbloqueio. Aplicação é recusada se CS2/VALORANT já estiver aberto: use antes da partida.

Antes de excluir, o backend C# abre cada arquivo com acesso exclusivo, verifica caminho final pelo handle, atributos, quantidade de hard links, tamanho e datas contra a prévia. Solicita exclusão pelo mesmo handle. Junctions que apontam para fora da raiz são recusadas, inclusive se o caminho textual parecia permitido. Não existe uma exclusão recursiva genérica de árvore.

Lixeira é independente e opcional, somente a do usuário corrente, pelo comando nativo `Clear-RecycleBin`. O menu mostra a prévia e exige confirmação explícita para excluir. Se já estiver vazia, não chama o esvaziamento.

**A exclusão é definitiva e não tem rollback.** O relatório em `%LOCALAPPDATA%/BNQQ/data/cleanup/GUID.json` é registro de atividade, não backup. Registra início e conclusão; se houver interrupção, o registro pode ficar `Running`, com contagens incompletas. Bytes reportados representam o tamanho lógico dos arquivos removidos; não são uma medição exata de espaço físico livre do volume.

Não exige reiniciar. Testes usam exclusivamente arquivos temporários próprios e uma Lixeira simulada; exercitam o backend real, arquivos bloqueados, links, junctions, mudanças após prévia e preservação de caches. Nunca esvaziam a Lixeira real no CI.
