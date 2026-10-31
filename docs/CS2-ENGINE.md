# CS2: configurações nativas e reversíveis (v2.3.0)

`cs2-engine` gera `bnqq_competitive.cfg`, acrescenta somente um bloco identificado ao `autoexec.cfg`, ajusta valores presentes em `cs2_video.txt` e cria o atalho de área de trabalho `BNQQ/CS2 - BNQQ.lnk`. Não altera binários, VPKs, serviços, prioridade/afinidade, drivers ou configurações de anti-cheat. Não abre o jogo.

## Perfis

| Opção | CompetitiveLow (padrão) | Minimum (explícito) |
| --- | --- | --- |
| MSAA / CMAA | Desligados | Desligados |
| Sombras globais | Low | Low |
| Sombras dinâmicas | All | Sun Only |
| Texturas, shaders, filtragem, partículas | Low | Low |
| Oclusão ambiente / VSync | Desligados | Desligados |
| HDR | Performance (`3`) | Performance (`3`) |
| FSR | Desligado (`0`) | Performance (`4`) |

Minimum reduz nitidez e pode remover pistas visuais de sombras de jogadores. Não é automaticamente o melhor perfil para competir. A resolução de saída, proporção, Hz, sensibilidade, binds e o valor existente de Reflex permanecem como estão. A redução de custo gráfico pode ajudar quando a GPU limita; não promete elevar FPS em cenários limitados por CPU.

Os valores foram conferidos no próprio menu instalado da Valve: `panorama/layout/settings/settings_video.vxml_c`, CS2 1.41.9.4, Steam build 26334290. Não são arquivos da Valve redistribuídos. A rotina exige vídeo schema 16, cada chave única/presente e os comandos arquivados esperados no `cs2_machine_convars.vcfg`; estruturas desconhecidas são recusadas.

## Uso

Feche o CS2 normalmente antes de aplicar/restaurar. O menu oferece a opção 26. Exemplos para Windows PowerShell 5.1:

```powershell
.\bnqq.ps1 cs2-engine -EngineAction plan -EngineMode CompetitiveLow
.\bnqq.ps1 cs2-engine -EngineAction apply -EngineMode Minimum
.\bnqq.ps1 cs2-engine -EngineAction restore -BackupFile 'CAMINHO_RETORNADO.json'
```

Detecção automática exige uma única pasta de usuário e uma única instalação. Para instalações múltiplas, informe `-GameConfigDirectory` (userdata/.../730/local/cfg), `-GameCfgDirectory` (game/csgo/cfg) e, se necessário, `-SteamExe`. Não escolhemos silenciosamente a conta errada.

O atalho usa `steam.exe -applaunch 730 +exec bnqq_competitive.cfg`. As opções já salvas no Steam não são apagadas nem editadas: configurações conflitantes existentes ainda devem ser consideradas. O bloco em autoexec também carrega o arquivo em inicializações normais que executem autoexec.

O cfg gerado contém somente `fps_max 0`, `fps_max_ui 120`, `cl_joystick_enabled false`, `cl_net_buffer_ticks` e uma mensagem de confirmação. O limite de FPS da partida fica ilimitado por escolha deste perfil; não é um limitador adaptativo. Não acrescentamos `-high`, `-threads`, `-novid`, `-nojoy`, comandos legados de mouse/interpolação ou remoção de céu, água e sangue. Não há macro, simulação de subtick, redução de recoil ou alteração da visibilidade de smoke.

`-EngineBufferTicks 0|1|2` é explícito e usa somente o ajuste nativo de buffer. O padrão 0 evita buffer adicional, não corrige perda/jitter da internet. Aumentar o buffer troca latência por tolerância a entregas irregulares. `rate` e configurações do Windows/mouse permanecem intactos; um cfg não configura aceleração do firmware do periférico.

## Backup e recuperação

Antes da primeira gravação de qualquer alvo, todos os quatro originais (incluindo ausência), hashes e resultados esperados ficam gravados em `%LOCALAPPDATA%/BNQQ/data/engineprofiles/GUID.json`. Cada arquivo usa troca atômica individual e verificação posterior. A operação completa de quatro arquivos **não** é uma transação atômica do sistema de arquivos; o journal permite recuperação de interrupções. Reaplicar um estado idêntico não sobrescreve o primeiro backup.

O rollback restaura bytes originais ou remove somente arquivos criados pelo perfil. Arquivos alterados depois por terceiros são preservados e sinalizados como conflito; os outros alvos ainda são recuperados. Não forçamos arquivos somente leitura nem substituímos cfg/atalho com conteúdo de proprietário desconhecido. Uma transação incompleta bloqueia nova aplicação até ser recuperada. Abrir CS2 durante a operação interrompe novas gravações e deixa o restante para recuperação com o jogo fechado.

Há integração com `recover` e `scripts/Incident-Rollback.ps1`. Não exige reiniciar Windows; os ajustes valem na próxima abertura do CS2. Testes usam instalações temporárias, sem abrir jogo nem produzir carga de hardware.

## Limites e fontes

Configurações normais não equivalem a uma garantia de risco zero de ban. A política FACEIT permite `.cfg` normais, mas proíbe configurações usadas para explorar/remover conteúdo para vantagem indevida: [política FACEIT](https://support.faceit.com/hc/en-us/articles/360015788779-What-is-deemed-to-be-a-cheat).

Consulte [opções de inicialização do Steam](https://help.steampowered.com/en/faqs/view/7D01-D2DD-D75E-2955), [Trusted Mode da Valve](https://help.steampowered.com/en/faqs/view/09A0-4879-4353-EF95) e [indicadores de rede do CS2](https://help.steampowered.com/en/faqs/view/5E6F-5B36-5485-F6B9). Não usamos injeção, desbloqueio de cvars protegidas ou flags para desativar segurança.

Aplicar e verificar arquivos prova a alteração, não o ganho. Só FrameBench comparável no mesmo cenário pode sustentar uma conclusão de FPS/p99/1% Low; não mede sozinho mouse-tela. Este módulo não inicia captura nem remove os bloqueios existentes por WHEA.
