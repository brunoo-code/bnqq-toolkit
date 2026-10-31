# Per-user startup preferences only. Never stops apps, services or anti-cheats.
function Get-BnqqStartupTargets {
    @([pscustomobject]@{Name='Spotify';Executable='Spotify.exe';Publisher='Spotify AB'},
      [pscustomobject]@{Name='RobloxPlayerBeta';Executable='RobloxPlayerBeta.exe';Publisher='Roblox Corporation'})
}
function Get-BnqqStartupExecutable {
    param([string]$Command)
    if(-not $Command -or $Command.Length -gt 32768 -or $Command -match '[\r\n\x00]'){throw 'Comando de inicializacao invalido'}
    $expanded=[Environment]::ExpandEnvironmentVariables($Command)
    $match=[regex]::Match($expanded,'^\s*"(?<exe>[^"\r\n]+\.exe)"(?:\s|$)','IgnoreCase')
    if(-not $match.Success){$match=[regex]::Match($expanded,'^\s*(?<exe>[a-z]:\\[^"\r\n]+?\.exe)(?:\s|$)','IgnoreCase')}
    if(-not $match.Success){throw 'Comando nao reconhecido; nenhum comando sera executado'}
    $exe=$match.Groups['exe'].Value
    if(-not [IO.Path]::IsPathRooted($exe) -or $exe.StartsWith('\\')){throw 'Executavel local exigido'}
    return [IO.Path]::GetFullPath($exe)
}
function Assert-BnqqStartupOperation {
    param($Op)
    $target=@(Get-BnqqStartupTargets|Where-Object Name -ceq $Op.Before.Name)
    if($target.Count -ne 1 -or $Op.Before.Path -cne 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -or $Op.Before.Kind -notin @('String','ExpandString') -or $Op.Before.Existed -isnot [bool] -or -not $Op.Before.Existed -or $Op.Before.KeyExisted -isnot [bool] -or -not $Op.Before.KeyExisted){throw 'Entrada de inicializacao nao admitida'}
    if([IO.Path]::GetFileName((Get-BnqqStartupExecutable $Op.Before.Value)) -ine $target[0].Executable){throw 'Executavel diverge da entrada de inicializacao'}
    $expected=[pscustomobject]@{Path=$Op.Before.Path;Name=$Op.Before.Name;KeyExisted=$true;Existed=$false;Kind=$null;Value=$null}
    if(-not (Test-BnqqSameValue $expected $Op.After)){throw 'Destino de inicializacao deve remover somente o valor escolhido'}
}
function Get-BnqqStartupSignature {
    param([string]$File,[string]$Publisher)
    if(-not (Test-Path -LiteralPath $File -PathType Leaf)){return $false}
    $signature=Get-AuthenticodeSignature -LiteralPath $File -ErrorAction Stop
    return ($signature.Status -eq 'Valid' -and $signature.SignerCertificate.Subject -match [regex]::Escape($Publisher))
}
function Get-BnqqStartupPlan {
    param([string[]]$Apps)
    $catalog=@(Get-BnqqStartupTargets)
    if(-not @($Apps).Count){$Apps=@($catalog.Name)}
    foreach($app in $Apps){if($app -cnotin $catalog.Name){throw 'Inicializacao fora da lista admitida'}}
    $ops=@();$items=@();$errors=@()
    foreach($app in @($Apps|Select-Object -Unique)){
        $target=$catalog|Where-Object Name -ceq $app
        try{
            $before=Get-RegSnapshot 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' $app
            if(-not $before.Existed){$items+=@([pscustomobject]@{Name=$app;State='RunEntryAbsent'});continue}
            $after=[pscustomobject]@{Path=$before.Path;Name=$before.Name;KeyExisted=$true;Existed=$false;Kind=$null;Value=$null}
            $op=[pscustomobject]@{Kind='Startup';Before=$before;After=$after}
            Assert-BnqqStartupOperation $op
            $file=Get-BnqqStartupExecutable $before.Value
            if(-not (Get-BnqqStartupSignature $file $target.Publisher)){throw 'Executavel/assinatura do fabricante nao verificado'}
            $ops+=@($op);$items+=@([pscustomobject]@{Name=$app;State='CanDisableAutostart';Executable=$target.Executable})
        }catch{$errors+=($app+': '+$_.Exception.Message)}
    }
    [pscustomobject]@{Status='Preview';Items=$items;Operations=$ops;Errors=$errors;Effect='Next sign-in; running apps, manual launch and anti-cheat services unchanged';FpsGainProven=$false;RebootRequired=$false}
}
function Set-BnqqStartupState {
    param($Op,$State,$Expected)
    if(-not (Test-BnqqSameValue (Get-RegSnapshot $Op.Before.Path $Op.Before.Name) $Expected)){throw 'Entrada de inicializacao mudou externamente'}
    Set-BnqqRegistrySnapshot $State
}
function Invoke-BnqqStartup {
    param([ValidateSet('plan','apply','restore')][string]$Action='plan',[string[]]$Apps,[string]$File)
    if($Action -eq 'restore'){
        $lock=Enter-BnqqStateLock
        try{
            $j=Get-Content -LiteralPath $File -Raw -ErrorAction Stop|ConvertFrom-Json
            if($j.Schema -ne 2 -or $j.Owner -cne (Get-BnqqOwner) -or @($j.Entries|Where-Object Kind -cne 'Startup').Count){throw 'Backup de inicializacao invalido'}
            return (Restore-BnqqJournal $File)
        }finally{$lock.Dispose()}
    }
    if($Action -eq 'apply' -and -not @($Apps).Count){throw 'Escolha explicitamente os apps de inicializacao'}
    $plan=Get-BnqqStartupPlan $Apps
    if($Action -eq 'plan'){return $plan}
    if($plan.Errors.Count){throw ($plan.Errors -join '; ')}
    if(-not $plan.Operations.Count){return [pscustomobject]@{Status='AlreadyConfigured';Changed=0;RebootRequired=$false}}
    # App launch preferences do not change hardware or run a workload. Existing
    # WHEA/HeavyQA gates for game sessions, power, clocks and captures stay intact.
    $lock=Enter-BnqqStateLock
    try{
        Assert-BnqqNoPendingJournal
        $journal=New-BnqqJournal 'startup-preferences'
        try{
            foreach($op in $plan.Operations){Invoke-BnqqJournalOperation $journal $op}
            $journal.Data.Status='Applied';Write-BnqqAtomicJson $journal.Data $journal.File
            # A completed persistent preference is not an unfinished game-session
            # journal. Keep failures in journals for recovery; archive only success.
            $root=[IO.Path]::GetFullPath((Get-BnqqDataRoot)).TrimEnd('\')+'\'
            $archive=[IO.Path]::GetFullPath((Join-Path $root ('startup-journals\'+[IO.Path]::GetFileName($journal.File))))
            if(-not [IO.Path]::GetFullPath($journal.File).StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or -not $archive.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Caminho de backup fora dos dados BNQQ'}
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($archive))
            [IO.File]::Move($journal.File,$archive)
            $journal.File=$archive
            [pscustomobject]@{Status='Applied';Changed=$plan.Operations.Count;Journal=$journal.File;Effect=$plan.Effect;FpsGainProven=$false;RebootRequired=$false}
        }catch{
            $failure=$_
            try{Restore-BnqqJournal $journal.File|Out-Null}catch{Write-BnqqNightLog 'STARTUP-RECOVERY-FAILED' $_.Exception.Message}
            throw $failure
        }
    }finally{$lock.Dispose()}
}
function Show-BnqqStartupMenu {
    Get-BnqqStartupPlan|Format-List
    $names=Read-Host 'Apps exatos separados por virgula: Spotify,RobloxPlayerBeta; vazio cancela'
    if(-not $names){return}
    $apps=@($names.Split(',')|ForEach-Object {$_.Trim()}|Where-Object {$_})
    if((Read-Host 'Desativar somente abertura automatica no logon? Digite SIM') -ceq 'SIM'){Invoke-BnqqStartup -Action apply -Apps $apps|Format-List}
}
