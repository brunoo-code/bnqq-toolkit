# Módulos da refatoração 1.8.3

| Módulo | Implementação ativa | Política e validação |
|---|---|---|
| 1 Estabilidade | Governance.ps1, Optimize.ps1 | WHEA fail-closed 72h; nenhuma energia por padrão; IDLEDISABLE AC opt-in com QA |
| 2 Watcher/Lasso | Watcher.ps1, BnqqProcessLasso.cs | Fila 64, rastreio até 512; serialização por lock, callback antigo rejeitado; sem APIs de mutação de memória/background |
| 3 Memória | Política do watcher | Nenhuma purga/trim/compressão automática; código antigo retirado |
| 4 Topologia | Topology.cs/ps1 | Máscaras reais por núcleo Win32, CIM só corrobora; multi-group/híbrida falha sem impor máscara; sem pares/ímpares presumidos |
| 5 DWM/MPO | Diagnostics.ps1, FrameBench.ps1 | Compare apresentação real; exclusiva não é garantia e Independent Flip pode evitar composição; sem OverlayTestMode |
| 6 Rede | NetworkAudit.ps1 | TCP/UDP explícitos, distribuição de sockets por PID e faixa efêmera em leitura; sem buffers/rotas/portas arbitrários |
| 7 Prioridades/MMCSS | RuntimeLatency.ps1 | AboveNormal explícito nos processos reais cs2 e VALORANT-Win64-Shipping; preserva prioridade anterior; não registra task MMCSS sem adesão das threads |
| 8 Chromium | Apps.ps1 | Sem flags novas; auditoria e limpeza opcional dos dois tokens invertidos com argumentos anteriores no journal |
| 9 Rollback | Core.ps1, Incident-Rollback.ps1 | Write-ahead atômico com flush e cópia anterior, allowlist de operações, lock exclusivo e conflito externo preservado; sem reset de fábrica |
| 10 HeavyQA | HeavyQA.ps1, StabilityLoad.cs | Digest CPU verificado e I/O com readback, WHEA durante carga e idle, fingerprint/boot/idade, falha invalida laudo |
| 11 SMBIOS | Diagnostics.ps1, hardware.json | Observado/declarado separados, PCI AMD apenas evidência parcial, nenhuma inferência de B550 por contagem de núcleos |
| 12 FrameBench | FrameBench.ps1 | Esquema/stream validado; percentis, cauda, baseline 3+3 e resultado inconclusivo por padrão |

Não existem medições novas de ganho em CS2/Valorant nesta refatoração. A plataforma de experimento foi corrigida; benefício depende de ensaio posterior. O mapa de funções/linhas anteriores fica em PATCH_PLAN_1.8.3.txt e o diff Git registra cada remoção e substituição.

A remoção dos pacotes é intencional: conservar uma função callable que desliga segurança, altera clocks ou grava chaves não verificadas contrariaria a política. Os arquivos retirados são listados em RETIRED_FILES.txt e permanecem recuperáveis no Git.
