# Game preferences only: no Windows, clock, power or driver mutations.
function Get-BnqqByteHash {
    param([byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','')}finally{$sha.Dispose()}
}
function Set-BnqqAtomicBytes {
    param([string]$Path,[byte[]]$Bytes)
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        $s=New-Object IO.FileStream($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$s.Write($Bytes,0,$Bytes.Length);$s.Flush($true)}finally{$s.Dispose()}
        [IO.File]::Replace($temp,$Path,($temp+'.old'),$true)
    }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)};if([IO.File]::Exists($temp+'.old')){[IO.File]::Delete($temp+'.old')}}
}
function Convert-BnqqMsaaProfile {
    param([byte[]]$Bytes,[ValidateSet(0,2,4,8)][int]$Msaa=2)
    # ASCII-only replacement on a one-byte view preserves every other original byte,
    # including BOM, line endings, encoding and unrelated preferences.
    $enc=[Text.Encoding]::GetEncoding(28591)
    $text=$enc.GetString($Bytes)
    $rx=New-Object Text.RegularExpressions.Regex('("setting\.msaa_samples"\s+")([0248])(")')
    if($rx.Matches($text).Count -ne 1){throw 'Schema MSAA ausente, duplicado ou desconhecido; nenhuma escrita'}
    $replacement='${1}'+$Msaa+'${3}'
    return ,$enc.GetBytes($rx.Replace($text,$replacement))
}
function Find-BnqqCs2Configs {
    param([string]$SteamRoot)
    if(-not $SteamRoot){$SteamRoot=(Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath}
    if(-not $SteamRoot){throw 'Steam nao encontrado; informe -GameConfigDirectory'}
    $users=Join-Path $SteamRoot 'userdata'
    if(-not (Test-Path -LiteralPath $users)){return @()}
    return @(Get-ChildItem -LiteralPath $users -Directory | Where-Object {$_.Name -match '^\d+$'} | ForEach-Object {
        $dir=Join-Path $_.FullName '730\local\cfg'
        if(Test-Path -LiteralPath (Join-Path $dir 'cs2_video.txt') -PathType Leaf){$dir}
    })
}
function Show-BnqqCompetitiveMenu {
    $dirs=@(Find-BnqqCs2Configs)
    if(-not $dirs.Count){throw 'Nenhum perfil CS2 encontrado'}
    for($i=0;$i -lt $dirs.Count;$i++){Write-Host ('[{0}] {1}' -f ($i+1),$dirs[$i])}
    $choice=1
    if($dirs.Count -gt 1){if(-not [int]::TryParse((Read-Host 'Selecione o perfil Steam'),[ref]$choice) -or $choice -lt 1 -or $choice -gt $dirs.Count){throw 'Selecao invalida'}}
    $directory=$dirs[$choice-1]
    Write-Host 'CS2 deve estar fechado. [1] MSAA 2x (reduz qualidade das bordas) [2] Restaurar backup [0] Sair'
    switch(Read-Host 'Acao'){
        '1' {
            Invoke-BnqqGameProfile -Directory $directory -Action plan | Format-List
            if((Read-Host 'Aplicar somente essa mudanca? Digite SIM') -ceq 'SIM'){Invoke-BnqqGameProfile -Directory $directory -Action apply | Format-List}
        }
        '2' {
            $folder=Join-Path (Get-BnqqDataRoot) 'gameprofiles'
            $backups=@(Get-ChildItem -LiteralPath $folder -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | ForEach-Object {
                try{$j=Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json;if($j.Schema -eq 'BNQQ.GameProfile.1' -and $j.Owner -eq (Get-BnqqOwner) -and $j.File -ieq (Join-Path $directory 'cs2_video.txt')){[pscustomobject]@{Path=$_.FullName;Date=$j.Generated;Status=$j.Status}}}catch{Write-Warning ('Backup ilegivel: '+$_.Name)}
            })
            if(-not $backups.Count){throw 'Sem backups deste perfil'}
            for($i=0;$i -lt $backups.Count;$i++){Write-Host ('[{0}] {1} {2}' -f ($i+1),$backups[$i].Date,$backups[$i].Status)}
            $index=0
            if(-not [int]::TryParse((Read-Host 'Backup para restaurar (0 cancela)'),[ref]$index) -or $index -lt 0 -or $index -gt $backups.Count){throw 'Selecao invalida'}
            if($index){Invoke-BnqqGameProfile -Directory $directory -Action restore -BackupFile $backups[$index-1].Path | Format-List}
        }
    }
}
function Invoke-BnqqGameProfile {
    param([string]$Directory,[ValidateSet('plan','apply','restore')][string]$Action='plan',
          [ValidateSet(0,2,4,8)][int]$Msaa=2,[string]$BackupFile)
    if(-not $Directory){
        $dirs=@(Find-BnqqCs2Configs)
        if($dirs.Count -ne 1){throw 'Perfil Steam ausente ou ambiguo; selecione -GameConfigDirectory ou use o menu competitivo'}
        $Directory=$dirs[0]
    }
    $path=[IO.Path]::GetFullPath((Join-Path $Directory 'cs2_video.txt'))
    if(-not [IO.File]::Exists($path)){throw 'Selecione a pasta cfg que contem cs2_video.txt'}
    $before=[IO.File]::ReadAllBytes($path)
    $after=Convert-BnqqMsaaProfile $before $Msaa
    if($Action -eq 'plan'){return [pscustomobject]@{File=$path;BeforeHash=(Get-BnqqByteHash $before);AfterHash=(Get-BnqqByteHash $after);Msaa=$Msaa;Effect='Menor custo de antialiasing; qualidade visual muda. Ganho e latencia nao garantidos.'}}
    if(Get-Process cs2 -ErrorAction SilentlyContinue){throw 'Feche CS2 normalmente antes de alterar/restaurar preferencias'}
    $lock=Enter-BnqqStateLock
    try {
        if($Action -eq 'restore'){
            $j=Get-Content -LiteralPath $BackupFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
            if($j.Schema -ne 'BNQQ.GameProfile.1' -or $j.Owner -ne (Get-BnqqOwner) -or $j.File -ine $path){throw 'Backup de outro alvo/usuario ou schema invalido'}
            $original=[Convert]::FromBase64String($j.Before)
            if((Get-BnqqByteHash $original) -cne $j.BeforeHash){throw 'Backup corrompido'}
            # A journal can only reverse the admitted MSAA transition, never inject other settings.
            $expected=Convert-BnqqMsaaProfile $original ([int]$j.Msaa)
            if((Get-BnqqByteHash $expected) -cne $j.AfterHash){throw 'Transicao de backup invalida'}
            $current=Get-BnqqByteHash ([IO.File]::ReadAllBytes($path))
            if($current -cne $j.BeforeHash){
                if($current -cne $j.AfterHash){throw 'Configuracao mudou externamente; restaure manualmente sem sobrescrever preferencias novas'}
                Set-BnqqAtomicBytes $path $original
            }
            $j.Status='Restored';Write-BnqqAtomicJson $j $BackupFile
            return [pscustomobject]@{Status='Restored';File=$path;Backup=$BackupFile}
        }
        if((Get-BnqqByteHash $before) -ceq (Get-BnqqByteHash $after)){return [pscustomobject]@{Status='AlreadyConfigured';File=$path}}
        $backup=Join-Path (Get-BnqqDataRoot) ('gameprofiles\'+[guid]::NewGuid().ToString('N')+'.json')
        $j=[pscustomobject]@{Schema='BNQQ.GameProfile.1';Owner=(Get-BnqqOwner);File=$path;Before=[Convert]::ToBase64String($before);BeforeHash=(Get-BnqqByteHash $before);AfterHash=(Get-BnqqByteHash $after);Msaa=$Msaa;Status='Prepared';Generated=[datetime]::UtcNow.ToString('o')}
        Write-BnqqAtomicJson $j $backup
        if((Get-BnqqByteHash ([IO.File]::ReadAllBytes($path))) -cne $j.BeforeHash){throw 'Arquivo mudou durante preparacao; escrita cancelada'}
        Set-BnqqAtomicBytes $path $after
        if((Get-BnqqByteHash ([IO.File]::ReadAllBytes($path))) -cne $j.AfterHash){throw ('Verificacao falhou; backup: '+$backup)}
        $j.Status='Applied';Write-BnqqAtomicJson $j $backup
        return [pscustomobject]@{Status='Applied';File=$path;Msaa=$Msaa;Backup=$backup;RequiresGameRestart=$true}
    }finally{$lock.Dispose()}
}
