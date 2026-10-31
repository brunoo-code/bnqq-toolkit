# Perfil competitivo: preferências do jogo

`competitive` altera apenas `setting.msaa_samples` em `cs2_video.txt` existente.
O valor inicial sugerido é 2x: menor custo de antialiasing que 8x, com perda de
qualidade nas bordas. Não há ganho de FPS ou latência garantido, especialmente
quando o limite é CPU. Não altera sombras, Reflex, resolução, Hz ou controles.

```powershell
.\bnqq.ps1 competitive -GameConfigDirectory 'PASTA\730\local\cfg' -CompetitiveAction plan
.\bnqq.ps1 competitive -GameConfigDirectory 'PASTA\730\local\cfg' -CompetitiveAction apply -Msaa 2
.\bnqq.ps1 competitive -GameConfigDirectory 'PASTA\730\local\cfg' -CompetitiveAction restore -BackupFile JOURNAL
```

Feche o jogo normalmente antes de aplicar/restaurar. Cada aplicação cria backup
único antes da escrita, com bytes originais e hashes. Escrita por substituição
atômica. Restore recusa arquivos modificados externamente; não sobrescreva essas
preferências. O jogo/Steam Cloud pode substituir configurações depois: reabra e
confirme no menu do jogo. Um crash entre escrita e confirmação deixa journal
Prepared recuperável pelo mesmo restore. Guarde o caminho emitido.

Esta categoria é uma preferência gráfica explícita, não um tweak de Windows ou
hardware. Não exige certificado HeavyQA nem libera ações bloqueadas por WHEA.
Adicionar módulos altera o fingerprint: o certificado anterior não aprova a nova
versão para alterações de Windows. Não reinicie apenas para aplicar este perfil.

## Entrada, vídeo e rede: limites e escolhas reais

* Mouse: polling alto exige suporte do jogo/CPU. A LAMZU documenta problemas de
  frame drop em alta frequência e atualização de mouse **e** receptor. Não faça
  flash automático. O toolkit não inventa leitura de polling via registro. Avalie
  1k/2k/4k/8k pelo software oficial; menor intervalo USB não prova menor mouse-tela.
* Teclado: actuation/Rapid Trigger são opções do firmware. Não enviar comandos
  HID desconhecidos nem aplicar valor mínimo universal: pode causar acionamentos
  involuntários. Configuração depende do modelo/firmware exatos.
* Monitor: identificar modelo antes de alterar OSD. Instant Mode, onde oferecido,
  reduz processamento; DyAc trata clareza de movimento e não é promessa de FPS.
  Não criar overclock de painel nem trocar resolução enquanto o jogo roda.
* Reflex: configuração integrada ao jogo; não empilhar Ultra Low Latency do driver
  esperando efeito adicional, pois Reflex prevalece. Boost não é ganho universal.
* Rede: ACK/NoDelay são TCP, não correção do tráfego UDP do gameplay. RSS depende
  do driver; ausência de objeto CIM não significa desabilitado. Não aplicar uma
  máscara RSS genérica. Desabilitar todos os offloads pode aumentar trabalho de
  CPU; interrupt moderation tem compromisso entre CPU e latência. Não alterar
  MTU, buffers, portas ou DNS como cura universal para ping. Filas no roteador
  e caminho da operadora não são removidas por chaves locais.

## Fontes primárias

* https://help.steampowered.com/en/faqs/view/418E-7A04-B0DA-9032
* https://www.nvidia.com/en-in/geforce/guides/system-latency-optimization-guide/
* https://lamzu.com/blogs/faq/how-do-i-use-the-maya-x-firmware-update-tools
* https://lamzu.com/blogs/faq/mouse-lags
* https://learn.microsoft.com/en-us/windows-hardware/drivers/network/introduction-to-receive-side-scaling
* https://learn.microsoft.com/en-us/windows-server/networking/technologies/network-subsystem/net-sub-performance-tuning-nics
* https://zowie.benq.com/en-ca/knowledge/common/120hz-gaming-monitors.html

O teste tests/GameProfile.ps1 exercita recusa de schema desconhecido/duplicado,
jogo aberto, alteração externa, preview sem escrita, backup único e rollback
idempotente exato. Não executa o jogo nem altera a configuração real do usuário.

## Acesso simplificado
O menu inicial oferece [5] Perfil competitivo CS2, incluindo selecao de conta Steam, preview, aplicacao e restauracao por backup selecionado. competitive sem -GameConfigDirectory descobre automaticamente uma unica conta; recusa ausencia/ambiguidade. No privado, config/competitive-personal.json guarda declaracoes dos perifericos como referencia, sem aplicar firmware ou polling automaticamente.
