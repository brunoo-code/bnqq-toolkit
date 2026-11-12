function Get-BnqqRecoveryCatalog {
    $root=Get-BnqqDataRoot
    foreach($folder in @('journals','startup-journals','app-lite','sessions','gameprofiles','engineprofiles','valorantprofiles','framepacing','legacy-migrations','network-sessions','nvidia-journals','nic-journals')){
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
        'BNQQ.AppLite.1' {return (Invoke-BnqqAppLite -Action restore -BackupFile $File)}
        'BNQQ.Nic.1' {
            $action=if($j.Status -eq 'Activated'){'restore-active'}else{'restore'}
            return (Invoke-BnqqNicPolicy -Action $action -File $File)
        }
        'BNQQ.Nvidia.1' {return (Invoke-BnqqGpuProfile -Action restore -File $File)}
        '2' {
            if(@($j.Entries|Where-Object {$_.Kind -notin @('Process','CpuSets','BackgroundPriority')}).Count -and -not (Test-BnqqAdmin)){throw 'Backup Windows exige administrador'}
            $lock=Enter-BnqqStateLock
            try{return (Restore-BnqqJournal $File)}finally{$lock.Dispose()}
        }
        'BNQQ.NetworkSession.1' {return (Invoke-BnqqNetworkSession -Action restore -File $File)}
        'BNQQ.Session.1' {return (Invoke-BnqqGameSession -Action restore -File $File)}
        'BNQQ.LegacyIFEO.1' {return (Invoke-BnqqLegacyMigration -Action restore -BackupFile $File)}
        'BNQQ.ValorantProfile.1' {return (Invoke-BnqqValorantProfile -Action restore -BackupFile $File)}
        'BNQQ.Cs2Engine.1' {return (Invoke-BnqqCs2Engine -Action restore -BackupFile $File)}
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
    while ($true) {
        Write-Host 'Restaurar configuracoes'
        Write-Host '  [1] Plano de energia'
        Write-Host '  [2] Edge e Chrome'
        Write-Host '  [3] Servicos opcionais'
        Write-Host '  [4] Aceleracao do ponteiro'
        Write-Host '  [5] Widgets'
        Write-Host '  [6] Inicializacao de aplicativos'
        Write-Host '  [7] Outros backups'
        Write-Host '  [0] Voltar'
        $choice = Read-Host 'Escolha o que restaurar'
        try {
            switch ($choice) {
                '1' { Set-BnqqWindowsPowerPlan -Action restore }
                '2' { Show-BnqqRecoveryBackups -Category Browsers }
                '3' { Set-BnqqOptionalServices -Restore }
                '4' { Set-BnqqPointerAcceleration -Restore }
                '5' { Set-BnqqWidgetsPolicy -Restore }
                '6' { Show-BnqqRecoveryBackups -Category Startup }
                '7' { Show-BnqqRecoveryBackups -Category Other }
                default { return }
            }
        } catch {
            Write-Warning $_.Exception.Message
        }
        Write-Host ''
    }
}

function Show-BnqqRecoveryBackups {
    param([ValidateSet('Browsers','Startup','Other')][string]$Category)
    $items = @(Get-BnqqRecoveryCatalog | Where-Object {
        if (-not $_.OwnsBackup -or $_.Status -eq 'Restored') { return $false }
        $folder = Split-Path (Split-Path $_.File -Parent) -Leaf
        switch ($Category) {
            'Browsers' { $folder -eq 'app-lite' }
            'Startup' { $folder -eq 'startup-journals' }
            'Other' { $folder -notin @('app-lite','startup-journals') }
        }
    })
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
