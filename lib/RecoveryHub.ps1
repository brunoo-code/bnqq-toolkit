function Get-BnqqRecoveryCatalog {
    $root=Get-BnqqDataRoot
    foreach($folder in @('journals','sessions','gameprofiles','framepacing','legacy-migrations')){
        foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $root $folder) -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)){
            try {
                $j=Get-Content $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
                [pscustomobject]@{File=$file.FullName;Schema=[string]$j.Schema;Status=$j.Status;OwnsBackup=($j.Owner -eq (Get-BnqqOwner));Modified=$file.LastWriteTime}
            }catch{[pscustomobject]@{File=$file.FullName;Schema='Unreadable';Status='InspectManually';OwnsBackup=$false;Modified=$file.LastWriteTime}}
        }
    }
}
function Invoke-BnqqRecovery {
    param([Parameter(Mandatory)][string]$File)
    $j=Get-Content -LiteralPath $File -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    if($j.Owner -ne (Get-BnqqOwner)){throw 'Backup de outro usuario; nenhuma restauracao iniciada'}
    switch([string]$j.Schema){
        '2' {
            if(-not (Test-BnqqAdmin)){throw 'Backup Windows exige administrador'}
            $lock=Enter-BnqqStateLock
            try{return (Restore-BnqqJournal $File)}finally{$lock.Dispose()}
        }
        'BNQQ.Session.1' {return (Invoke-BnqqGameSession -Action restore -File $File)}
        'BNQQ.LegacyIFEO.1' {return (Invoke-BnqqLegacyMigration -Action restore -BackupFile $File)}
        'BNQQ.GameProfile.1' {
            if(-not $j.File -or (Split-Path $j.File -Leaf) -ine 'cs2_video.txt'){throw 'Alvo grafico invalido'}
            return (Invoke-BnqqGameProfile -Directory (Split-Path $j.File -Parent) -Action restore -BackupFile $File)
        }
        'BNQQ.FramePacing.1' {
            if(-not $j.File -or (Split-Path $j.File -Leaf) -ine 'cs2_machine_convars.vcfg'){throw 'Alvo de caps invalido'}
            return (Invoke-BnqqFramePacing -Directory (Split-Path $j.File -Parent) -Action restore -BackupFile $File)
        }
        default {throw 'Backup legado/desconhecido: sem reset de Windows ou defaults presumidos'}
    }
}
function Show-BnqqRecoveryMenu {
    $items=@(Get-BnqqRecoveryCatalog | Where-Object OwnsBackup)
    if(-not $items.Count){Write-Host 'Sem backups deste usuario';return}
    for($i=0;$i -lt $items.Count;$i++){Write-Host ('[{0}] {1} | {2} | {3} | {4}' -f ($i+1),$items[$i].Schema,$items[$i].Status,$items[$i].Modified,$items[$i].File)}
    $selection=0
    if(-not [int]::TryParse((Read-Host 'Backup para restaurar; 0 cancela'),[ref]$selection) -or $selection -lt 0 -or $selection -gt $items.Count){throw 'Selecao invalida'}
    if($selection){Invoke-BnqqRecovery $items[$selection-1].File | ConvertTo-Json -Depth 8}
}
function Show-BnqqSessionMenu {
    Write-Host 'Sessao temporaria: reduz prioridade de apps escolhidos para BelowNormal. Nenhum app e fechado/suspenso.'
    Write-Host ('Admitidos: '+((Get-BnqqSessionAllowedApps) -join ', '))
    $text=Read-Host 'Digite nomes separados por virgula; vazio cancela'
    if(-not $text.Trim()){return}
    $apps=@($text.Split(',')|ForEach-Object {$_.Trim()}|Where-Object {$_})
    Invoke-BnqqGameSession -Action plan -Apps $apps | Format-List
    $game=Read-Host 'Jogo aberto: 1=CS2, 2=Valorant; outro cancela'
    if($game -notin @('1','2')){return}
    $name=if($game -eq '1'){'cs2.exe'}else{'VALORANT-Win64-Shipping.exe'}
    Write-Host 'Aguarda jogo fechar; Ctrl+C solicita saida/restauracao. Se a janela for morta, use Recuperacao na proxima abertura.'
    Invoke-BnqqGameSession -Action run -Apps $apps -Game $name | Format-List
}
