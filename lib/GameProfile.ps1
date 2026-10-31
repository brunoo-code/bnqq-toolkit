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
function Invoke-BnqqGameProfile {
    param([Parameter(Mandatory)][string]$Directory,[ValidateSet('plan','apply','restore')][string]$Action='plan',
          [ValidateSet(0,2,4,8)][int]$Msaa=2,[string]$BackupFile)
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
