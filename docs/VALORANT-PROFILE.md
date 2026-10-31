# VALORANT: perfil local baixo (v2.3.1)

O comando `valorant` edita exclusivamente sete chaves **já presentes** em `[ScalabilityGroups]` no `GameUserSettings.ini`: `sg.ShadowQuality`, `sg.AntiAliasingQuality`, `sg.PostProcessQuality`, `sg.TextureQuality`, `sg.EffectsQuality`, `sg.FoliageQuality` e `sg.ShadingQuality`. Define nível `0`, sem inserir seções/chaves ausentes nem alterar outros grupos, resolução, sensibilidade ou binds.

Na [documentação de escalabilidade da Epic](https://dev.epicgames.com/documentation/unreal-engine/customizing-device-profiles-and-scalability-for-android?application_version=4.27), `0` é o nível Low do framework. Isso **não comprova** que todos esses grupos sejam consumidos pelo VALORANT, correspondam às opções de seu menu ou produzam ganho de FPS. O cliente pode ignorar ou substituir valores. O comando informa `FpsGainProven=false` e efeito de runtime não verificado. Não é uma remoção de conteúdo da engine.

Para ajustes com suporte do fabricante, a [Riot recomenda as opções do menu gráfico](https://support.riotgames.com/en-us/riot/performance/optimize-graphics-settings-for-better-fps-windows-and-mac). Não divulgamos redução de custo GPU/frametime como medida até haver confirmação de que os valores foram aceitos e uma comparação controlada.

## Uso

Feche normalmente o jogo e o cliente Riot antes de aplicar/restaurar. Nenhum processo é encerrado pelo comando. O menu 27 oferece visualização e aplicação explícita nos perfis encontrados.

```powershell
.\bnqq.ps1 valorant -ValorantAction plan
.\bnqq.ps1 valorant -ValorantAction apply -AllValorantProfiles
.\bnqq.ps1 valorant -ValorantAction apply -ValorantProfilePath 'CAMINHO_COMPLETO_DO_PERFIL.ini'
.\bnqq.ps1 valorant -ValorantAction restore -BackupFile 'JOURNAL_RETORNADO.json'
```

Só aceita arquivos de contas em `%LOCALAPPDATA%/VALORANT/Saved/Config/{GUID-regiao}/WindowsClient/GameUserSettings.ini` ou `Windows/GameUserSettings.ini`. O arquivo global sem conta não é escolhido. Havendo múltiplas contas, aplicação exige seleção explícita ou `-AllValorantProfiles`; nunca inferimos a conta ativa pela data de modificação. Há limite de 16 arquivos por transação.

## Segurança das preferências

- Mantém arquivos graváveis. Não impõe somente leitura para disputar atualizações do cliente. Arquivo já protegido é recusado na aplicação, sem limpar seus atributos.
- Preserva todos os bytes fora dos sete valores, inclusive comentários, linhas, BOM UTF-8 e outras seções. UTF-16, seções/chaves duplicadas, valores fora de 0–3, arquivos grandes e links são recusados.
- Salva todos os originais e resultados esperados em um único journal durável antes da primeira gravação. Cada substituição de arquivo é atômica, mas a transação inteira de múltiplos arquivos depende de recuperação pelo journal.
- Backups em `%LOCALAPPDATA%/BNQQ/data/valorantprofiles/GUID.json` têm validação de usuário, escopo, hashes e da transição permitida. Reaplicar um estado idêntico não substitui o backup anterior.
- Reversão restaura bytes anteriores. Alterações externas são preservadas como conflito; outros perfis ainda podem ser recuperados. Transação incompleta bloqueia uma nova aplicação.
- Se o jogo/cliente abrir durante a operação, novas gravações são interrompidas; a recuperação pode ser concluída com ambos fechados pelo comando `recover` ou `scripts/Incident-Rollback.ps1`.

Não requer reiniciar Windows. Não abre o jogo, faz captura, executa carga de hardware ou modifica caches de shaders.

## Vanguard e integridade competitiva

Não altera `vgc`, `vgk`, prioridade ou afinidade de serviços Riot, políticas de segurança, startup, identificadores de hardware ou SMBIOS. Não usa ofuscação, integração com spoofer, camuflagem, injeção ou bypass de anti-cheat. Não pressupõe que o serviço `vgc.exe` seja a origem de DPC/ISR sem rastreamento que sustente essa atribuição.

Não existe garantia de “zero ban” nem certificação Riot deste toolkit. A [política de aplicativos de terceiros da Riot](https://support.riotgames.com/en-us/riot/events/third-party-applications) deve ser respeitada. Este módulo é somente um editor explícito de preferências locais existentes; não busca contornar limitações competitivas.
