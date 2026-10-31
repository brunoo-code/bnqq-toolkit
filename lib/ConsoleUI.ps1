# Presentation only: importing/rendering never probes hardware or applies settings.
function Show-BnqqConsoleMenu {
    param([string]$Version,[ValidateSet('PUBLIC','PRIVATE')][string]$Edition='PUBLIC')
    $logo=@(
        '   ____  _   _  ___   ___  ',
        '  | __ )| \ | |/ _ \ / _ \ ',
        '  |  _ \|  \| | | | | | | |',
        '  | |_) | |\  | |_| | |_| |',
        '  |____/|_| \_|\__\_\\__\_\',
        '        system engineering'
    )
    Write-Host ''
    foreach($line in $logo){Write-Host ('  '+$line) -ForegroundColor Cyan}
    Write-Host ('  BNQQ OPTIMIZER v{0} | {1} | {2}' -f $Version,$Edition,(Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor DarkGray
    Write-Host '  CS2 / VALORANT' -ForegroundColor DarkGray
    Write-Host ''
    $labels=@(
        'Diagnostico do PC',
        'Analise de rede',
        'Monitor e apresentacao de quadros',
        'Apps e atalhos Chromium',
        'Preferencias graficas do CS2',
        'Limite de FPS do menu do CS2',
        'Prioridades dos apps em segundo plano',
        'Recuperar estado anterior',
        'Migracao de ajustes antigos',
        'Controle de upload por aplicativo',
        'Nucleos dos apps em segundo plano',
        'Perfil de energia da GPU',
        'Memoria e armazenamento NVMe',
        'Checksums do adaptador de rede',
        'Sessao Focus',
        'Inventario de drivers',
        'Sessao competitiva integrada - plano',
        'Gerador sintetico C# - plano',
        'Estabilidade / prontidao',
        'Temporizadores - consulta',
        'USB e perifericos - consulta',
        'Seguranca / VBS - consulta',
        'Analise DPC/ISR - formato de entrada',
        'Ajuda e comandos'
    )
    for($i=0;$i -lt $labels.Count;$i++){
        Write-Host ('  '+('[{0}]' -f ($i+1)).PadRight(5)+$labels[$i]) -ForegroundColor Gray
    }
    Write-Host '  [0]  Sair' -ForegroundColor DarkGray
    Write-Host ''
}
