# Migração e limites de recuperação

Esta é uma alteração incompatível com a CLI/TUI e os perfis 1.8.2. `competitive`, `max`, `extreme`, `pro`, `god`, `ultimate`, `focus`, `trim`, `memtune`, `hid`, `acpi`, `msi` e afins não executam mais os pacotes antigos. A interface apresenta diagnóstico e experimentos admitidos. O código anterior permanece no histórico Git.

## Estado da máquina existente

Publicar fonte ou gerar EXE **não migra o Windows**. Watcher/Audio Isolation antigos podem continuar vivos com suas funções já carregadas na memória. Não foram encerrados, desinstalados ou reconfigurados durante esta tarefa. Tarefas antigas com `-DeepFreeze` são recusadas pelo novo script se reiniciarem; a tarefa deve ser revista, não silenciosamente reinterpretada. Pare cooperativamente a versão v2 com `watch -WatcherAction stop`. Uma versão antiga sem protocolo não pode receber a mesma garantia.

Antes de trocar tarefas antigas: preserve os backups/reports originais; recupere apps suspensos pelo procedimento original quando possível; revise tarefa/argumentos e alterações pendentes. Não mate o processo para depois presumir que o finally restaurou tudo. Se o processo antigo já caiu, suspensões, afinidades e locks podem não ter snapshot recuperável.

## O que o rollback garante e o que não pode reconstruir

O journal v2 cobre **todas as mutações admitidas pelo novo programa**, registra o estado anterior antes da escrita e verifica a restauração. Não sabe a condição histórica anterior a alterações sem backup. Não pode reconstruir configuração de fábrica de um Windows personalizado ou mudanças feitas por terceiros.

Use `restore -BackupFile` para um journal v2 pendente. Conflitos com mudanças externas não são sobrescritos: ficam `NeedsRecovery`. Examine `.previous` se o JSON principal tiver sido danificado; nunca edite um journal para contornar validações. A ausência de snapshot, um JSON legado ou outro proprietário é erro explícito. Não há um reset automático destrutivo.

Energia mantém DC e demais políticas; o experimento altera apenas IDLEDISABLE AC do plano capturado. Durante uma operação parcial, só estados intermediários compatíveis com antes/depois podem ser recuperados. Processo que saiu ou cujo PID foi reutilizado não é alterado.

## Artefatos antigos

Não apague `%LOCALAPPDATA%\BNQQ_Optimizer\1.8.2`, `backups` ou `reports` dos repositórios: podem conter os únicos snapshots legados. O launcher 1.8.3 usa diretórios únicos por payload e dados v2 fora deles. O EXE público não contém licença e o build público não possui IncludeLicense; não há gate de HWID/licença.

Os antigos guias que anunciavam pacotes/porcentagens foram substituídos. Nenhum objeto Git do histórico privado, chave de assinatura ou módulo de licença foi importado para o público. Backups de usuário e nenhum segredo novo são enviados ao Git.
