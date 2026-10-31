# Narrow migration of known old BNQQ IFEO overrides. Never import arbitrary reg files.
function Get-BnqqLegacyTargets {
    foreach($game in @('cs2.exe','VALORANT-Win64-Shipping.exe')){
        foreach($name in @('CpuPriorityClass','IoPriority','PagePriority')){
            [pscustomobject]@{Path=('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\'+$game+'\PerfOptions');Name=$name;LegacyValue=$(if($name -eq 'PagePriority'){5}else{3})}
        }
    }
}
function Get-BnqqLegacyMigrationPlan {
    param([Parameter(Mandatory)][string[]]$Files)
    if($Files.Count -lt 1 -or $Files.Count -gt 64){throw 'Selecione entre 1 e 64 snapshots legados'}
    $sources=@(foreach($file in $Files){
        $item=Get-Item -LiteralPath $file -ErrorAction Stop
        if($item.Length -gt 2MB){throw 'Snapshot excede limite de 2MB'}
        $bytes=[IO.File]::ReadAllBytes($item.FullName)
        $raw=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xfeff)
        $d=$raw|ConvertFrom-Json
        if(-not $d.Created -or -not $d.Entries -or @($d.Entries).Count -gt 20000){throw 'Snapshot legado sem Created/Entries ou excede limite'}
        $created=[datetimeoffset]::Parse([string]$d.Created,[Globalization.CultureInfo]::InvariantCulture)
        if($created -gt [datetimeoffset]::UtcNow){throw 'Snapshot com data futura'}
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$hash=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')}finally{$sha.Dispose()}
        [pscustomobject]@{File=$item.FullName;Hash=$hash;Created=$created.UtcDateTime;Entries=@($d.Entries)}
    })
    foreach($target in @(Get-BnqqLegacyTargets)){
        $matches=@(foreach($source in $sources){
            $entries=@($source.Entries|Where-Object {([regex]::Replace([string]$_.Path,'\\+','\')) -ieq $target.Path -and $_.Name -ceq $target.Name})
            if($entries.Count -gt 1){throw 'Snapshot com entradas duplicadas para mesmo alvo'}
            if($entries.Count){[pscustomobject]@{Source=$source;Entry=$entries[0]}}
        })
        $matches=@($matches|Sort-Object {$_.Source.Created})
        if(-not $matches.Count){continue}
        $first=$matches[0]
        # Equal dates with differing state are ambiguous; never invent chronology.
        foreach($other in @($matches|Where-Object {$_.Source.Created -eq $first.Source.Created})){
            if(-not (Test-BnqqSameValue $other.Entry $first.Entry)){throw 'Historico ambiguo com mesmo timestamp'}
        }
        $current=Get-RegSnapshot $target.Path $target.Name
        $action=if($first.Entry.Existed -isnot [bool]){'InvalidOriginal'}elseif($first.Entry.Existed){'OriginalAlreadyExisted'}elseif($null -ne $first.Entry.Kind -or $null -ne $first.Entry.Value){'InvalidOriginal'}elseif(-not $current.Existed){'AlreadyAbsent'}elseif($current.Kind -ne 'DWord' -or [int64]$current.Value -ne $target.LegacyValue){'ConflictCurrentValue'}else{'RemoveKnownOverride'}
        [pscustomobject]@{Path=$target.Path;Name=$target.Name;Action=$action;Current=$current;LegacyValue=$target.LegacyValue;Original=$first.Entry;SourceFile=$first.Source.File;SourceHash=$first.Source.Hash;SourceCreated=$first.Source.Created.ToUniversalTime().ToString('o');Limit='Snapshot selecionado pelo operador; timestamp/hash nao autenticam origem ou completude do historico'}
    }
}
function Assert-BnqqLegacyEntry {
    param($Entry)
    if($Entry.Before.Existed -isnot [bool] -or $Entry.Before.KeyExisted -ne $true -or $Entry.After.Existed -isnot [bool] -or $Entry.After.KeyExisted -isnot [bool]){throw 'Flags de snapshot invalidas'}
    $targets=@(Get-BnqqLegacyTargets|Where-Object {$_.Path -ieq $Entry.Before.Path -and $_.Name -ceq $Entry.Before.Name})
    if($targets.Count -ne 1 -or $Entry.Before.Kind -ne 'DWord' -or -not $Entry.Before.Existed -or [int64]$Entry.Before.Value -ne $targets[0].LegacyValue -or $Entry.After.Path -ine $Entry.Before.Path -or $Entry.After.Name -cne $Entry.Before.Name -or $Entry.After.Existed -ne $false -or $Entry.After.KeyExisted -ne $true -or $null -ne $Entry.After.Kind -or $null -ne $Entry.After.Value){throw 'Transicao de migracao fora da lista admitida'}
}
function Restore-BnqqLegacyMigration {
    param([Parameter(Mandatory)][string]$File)
    $j=Get-Content -LiteralPath $File -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json
    if($j.Schema -ne 'BNQQ.LegacyIFEO.1' -or $j.Owner -ne (Get-BnqqOwner) -or @($j.Entries).Count -gt 6){throw 'Journal de migracao invalido ou de outro usuario'}
    foreach($e in @($j.Entries)){Assert-BnqqLegacyEntry $e}
    $errors=@()
    foreach($e in @($j.Entries)){
        if($e.Status -eq 'Restored'){continue}
        try {
            $current=Get-RegSnapshot $e.Before.Path $e.Before.Name
            if(-not (Test-BnqqSameValue $current $e.Before)){
                if(-not (Test-BnqqSameValue $current $e.After)){throw 'Registro mudou externamente; recuperacao recusada'}
                Set-BnqqRegistrySnapshot $e.Before
                if(-not (Test-BnqqSameValue (Get-RegSnapshot $e.Before.Path $e.Before.Name) $e.Before)){throw 'Recuperacao nao verificada'}
            }
            $e.Status='Restored'
        }catch{$errors+=$_.Exception.Message}
        Write-BnqqAtomicJson $j $File
    }
    $j.Status=if($errors.Count){'NeedsRecovery'}else{'Restored'};Write-BnqqAtomicJson $j $File
    if($errors.Count){throw ($errors -join '; ')}
    return $j
}
function Invoke-BnqqLegacyMigration {
    param([ValidateSet('plan','apply','restore')][string]$Action='plan',[string[]]$Files,[string]$BackupFile)
    if($Action -eq 'plan'){return @(Get-BnqqLegacyMigrationPlan $Files)}
    if(-not (Test-BnqqAdmin)){throw 'Migracao/recuperacao de registro exige administrador'}
    if($Action -eq 'apply'){Assert-BnqqHeavyQa}
    $lock=Enter-BnqqStateLock
    try {
        if($Action -eq 'restore'){return (Restore-BnqqLegacyMigration $BackupFile)}
        Assert-BnqqNoPendingJournal
        $folder=Join-Path (Get-BnqqDataRoot) 'legacy-migrations'
        foreach($priorFile in @(Get-ChildItem -LiteralPath $folder -Filter '*.json' -File -ErrorAction SilentlyContinue)){
            $prior=Get-Content $priorFile.FullName -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json
            if($prior.Status -ne 'Restored'){throw ('Migracao anterior ainda nao desfeita/recuperada: '+$priorFile.FullName)}
        }
        $plan=@(Get-BnqqLegacyMigrationPlan $Files)
        $actions=@($plan|Where-Object Action -eq 'RemoveKnownOverride')
        if(@($plan|Where-Object {$_.Action -in @('InvalidOriginal','ConflictCurrentValue')}).Count){throw 'Plano tem conflitos; nenhuma escrita iniciada'}
        if(-not $actions.Count){return [pscustomobject]@{Status='NoChanges';Plan=$plan}}
        $file=Join-Path (Get-BnqqDataRoot) ('legacy-migrations\'+[guid]::NewGuid().ToString('N')+'.json')
        $j=[pscustomobject]@{Schema='BNQQ.LegacyIFEO.1';Owner=(Get-BnqqOwner);Created=[datetime]::UtcNow.ToString('o');Status='Prepared';Entries=@()}
        Write-BnqqAtomicJson $j $file
        try {
            foreach($a in $actions){
                if((Get-FileHash $a.SourceFile -Algorithm SHA256).Hash -cne $a.SourceHash){throw 'Snapshot de origem mudou'}
                if(-not (Test-BnqqSameValue (Get-RegSnapshot $a.Path $a.Name) $a.Current)){throw 'Registro mudou durante preparacao'}
                $after=[pscustomobject]@{Path=$a.Path;Name=$a.Name;KeyExisted=$true;Existed=$false;Kind=$null;Value=$null}
                $e=[pscustomobject]@{Before=$a.Current;After=$after;SourceFile=$a.SourceFile;SourceHash=$a.SourceHash;SourceCreated=$a.SourceCreated;Original=$a.Original;Status='Prepared'}
                Assert-BnqqLegacyEntry $e
                $j.Entries=@($j.Entries)+@($e);Write-BnqqAtomicJson $j $file
                Set-BnqqRegistrySnapshot $after
                if(-not (Test-BnqqSameValue (Get-RegSnapshot $a.Path $a.Name) $after)){throw 'Remocao nao verificada'}
                $e.Status='Applied';Write-BnqqAtomicJson $j $file
            }
            $j.Status='Applied';Write-BnqqAtomicJson $j $file
        }catch{ $original=$_;Restore-BnqqLegacyMigration $file|Out-Null;throw $original }
        return [pscustomobject]@{Status='Applied';Removed=$actions.Count;Backup=$file;Effect='Overrides legados removidos; efeito em FPS nao demonstrado. Apenas proximas instancias dos jogos leem IFEO.'}
    }finally{$lock.Dispose()}
}
function Show-BnqqLegacyMigrationMenu {
    Write-Host 'Migracao limitada a IFEO de CS2/Valorant. Use apenas backups conhecidos deste Windows.'
    $directory=Read-Host 'Pasta com backup-*.json; vazio cancela'
    if(-not $directory.Trim()){return}
    $files=@(Get-ChildItem -LiteralPath $directory -Filter 'backup-*.json' -File -ErrorAction Stop | Select-Object -ExpandProperty FullName)
    if(-not $files.Count){throw 'Nenhum snapshot backup-*.json encontrado'}
    $plan=@(Invoke-BnqqLegacyMigration -Action plan -Files $files)
    $plan|Select-Object Path,Name,Action,SourceFile,SourceCreated|Format-List
    Write-Host 'Apenas ausencia original comprovada nos arquivos escolhidos. Datas/hashes nao autenticam origem. Aplicar exige governanca valida.'
    if((Read-Host 'Para aplicar este plano digite MIGRAR; outro texto cancela') -ceq 'MIGRAR'){
        Invoke-BnqqLegacyMigration -Action apply -Files $files|Format-List
    }
}
