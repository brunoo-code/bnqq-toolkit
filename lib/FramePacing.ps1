# Changes game-owned frame caps only. No timers, driver flags, power or affinity.
function Convert-BnqqFrameCaps {
    param([byte[]]$Bytes,[int]$GameCap=-1,[int]$MenuCap=120)
    if(($GameCap -ne -1 -and $GameCap -ne 0 -and ($GameCap -lt 60 -or $GameCap -gt 1000)) -or $MenuCap -lt 30 -or $MenuCap -gt 240){throw 'Cap invalido: partida -1(preservar), 0(sem limite) ou 60..1000; menu 30..240'}
    $enc=[Text.Encoding]::GetEncoding(28591);$text=$enc.GetString($Bytes)
    foreach($entry in @(@{Pattern='("fps_max"\s+")(\d+)(")';Value=$GameCap},@{Pattern='("fps_max_ui(?:\$2)?"\s+")(\d+)(")';Value=$MenuCap})){
        $rx=New-Object Text.RegularExpressions.Regex($entry.Pattern)
        if($rx.Matches($text).Count -ne 1){throw 'Schema de caps ausente/ambiguo; nenhuma escrita'}
        if($entry.Value -ne -1){$text=$rx.Replace($text,('${1}'+$entry.Value+'${3}'))}
    }
    return ,$enc.GetBytes($text)
}
function Invoke-BnqqFramePacing {
    param([string]$Directory,[ValidateSet('plan','apply','restore')][string]$Action='plan',
          [int]$GameCap=-1,[int]$MenuCap=120,[string]$BackupFile)
    if(-not $Directory){
        $dirs=@(Find-BnqqCs2Configs)
        if($dirs.Count -ne 1){throw 'Perfil Steam ausente ou ambiguo; selecione -GameConfigDirectory ou use o menu competitivo'}
        $Directory=$dirs[0]
    }
    $path=[IO.Path]::GetFullPath((Join-Path $Directory 'cs2_machine_convars.vcfg'))
    if(-not [IO.File]::Exists($path)){throw 'Selecione a pasta cfg que contem cs2_machine_convars.vcfg'}
    $before=[IO.File]::ReadAllBytes($path)
    $after=Convert-BnqqFrameCaps $before $GameCap $MenuCap
    if($Action -eq 'plan'){return [pscustomobject]@{File=$path;BeforeHash=(Get-BnqqByteHash $before);AfterHash=(Get-BnqqByteHash $after);GameCap=$GameCap;MenuCap=$MenuCap;Effect='Limite do menu reduz trabalho fora da partida. Cap de partida e opcional; pode reduzir FPS maximo e nao garante menor latencia.'}}
    if(Get-Process cs2 -ErrorAction SilentlyContinue){throw 'Feche CS2 normalmente antes de alterar/restaurar preferencias'}
    $lock=Enter-BnqqStateLock
    try {
        if($Action -eq 'restore'){
            $j=Get-Content -LiteralPath $BackupFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
            if($j.Schema -ne 'BNQQ.FramePacing.1' -or $j.Owner -ne (Get-BnqqOwner) -or $j.File -ine $path){throw 'Backup de outro alvo/usuario ou schema invalido'}
            $original=[Convert]::FromBase64String($j.Before)
            if((Get-BnqqByteHash $original) -cne $j.BeforeHash){throw 'Backup corrompido'}
            # A journal can only reverse the admitted frame-cap transition, never inject other settings.
            $expected=Convert-BnqqFrameCaps $original ([int]$j.GameCap) ([int]$j.MenuCap)
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
        $backup=Join-Path (Get-BnqqDataRoot) ('framepacing\'+[guid]::NewGuid().ToString('N')+'.json')
        $j=[pscustomobject]@{Schema='BNQQ.FramePacing.1';Owner=(Get-BnqqOwner);File=$path;Before=[Convert]::ToBase64String($before);BeforeHash=(Get-BnqqByteHash $before);AfterHash=(Get-BnqqByteHash $after);GameCap=$GameCap;MenuCap=$MenuCap;Status='Prepared';Generated=[datetime]::UtcNow.ToString('o')}
        Write-BnqqAtomicJson $j $backup
        if((Get-BnqqByteHash ([IO.File]::ReadAllBytes($path))) -cne $j.BeforeHash){throw 'Arquivo mudou durante preparacao; escrita cancelada'}
        Set-BnqqAtomicBytes $path $after
        if((Get-BnqqByteHash ([IO.File]::ReadAllBytes($path))) -cne $j.AfterHash){throw ('Verificacao falhou; backup: '+$backup)}
        $j.Status='Applied';Write-BnqqAtomicJson $j $backup
        return [pscustomobject]@{Status='Applied';File=$path;GameCap=$GameCap;MenuCap=$MenuCap;Backup=$backup;RequiresGameRestart=$true}
    }finally{$lock.Dispose()}
}
