# Validação pública v1.8.3

Origem do núcleo: optimizer-bnqq a9d03250520980eea0d99713cf4380a1a18ed624. Distribuição pública sem licença, keygen, allowlist remota e preset pessoal.

* tests/Regression.ps1: 86 verificações locais do núcleo; nenhuma mutação do Windows/jogos.
* tests/EffectiveBench.ps1: 22 verificações com fixtures, inclusive guard em job isolado, deltas, baseline, bloqueios de interferência e ausência de veredito com um par.
* tests/Launcher.ps1: manifesto/payload, adulteração recusada e cinco casos de quoting sem executar Main/UAC.
* build.ps1 -KeepBuild: executável público recompilado; payload verificado sem arquivos privados.
* Referência local do operador lida por framebench -Effective -DryRun; captura preservada.
* Nenhuma tarefa foi desativada, nenhum processo de jogo foi alterado, nenhum HeavyQA prolongado ou benchmark novo foi executado.
* Estado limpo exige migração de tarefas legadas, HeavyQA recente e identidade/topologia verificáveis. Um par gera relatório exploratório; não demonstra ganho causal.
* Alterações em relação ao upstream privado e comandos: PUBLIC_SYNC.md. Logs de runtime e referências locais não são publicados.
