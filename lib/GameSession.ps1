# Opt-in, fixed-participant session. No suspend/kill, affinity, timer or memory purge.
function Get-BnqqSessionAllowedApps {
    return @('msedge','chrome','firefox','Discord','OneDrive','LAMZU Aurora','AJAZZ Driver')
}
function Get-BnqqSessionProcess {
    param([int]$ProcessId)
    $p=Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if(-not $p){return $null}
    try{$handle=$p.Handle;Assert-BnqqCpuProcessScope $p $handle;return [pscustomobject]@{ProcessId=$p.Id;Name=$p.ProcessName;StartTime=$p.StartTime.ToUniversalTime().ToString('o');Priority=$p.PriorityClass.ToString()}}
    finally{$p.Dispose()}
}
function Set-BnqqSessionPriority {
    param([int]$ProcessId,[string]$Priority,$Expected)
    $p=Get-Process -Id $ProcessId -ErrorAction Stop
    try {
        # Open/cache the process handle before checking identity and mutating that object.
        $handle=$p.Handle
        Assert-BnqqCpuProcessScope $p $handle
        if(-not $Expected -or $p.StartTime.ToUniversalTime().ToString('o') -cne $Expected.StartTime -or $p.ProcessName -ine $Expected.Name){throw 'Identidade do processo mudou; escrita cancelada'}
        if($p.PriorityClass.ToString() -cne $Expected.Priority){throw 'Prioridade mudou antes da escrita; nao sobrescrever'}
        $p.PriorityClass=$Priority
    }finally{$p.Dispose()}
}
function Get-BnqqSessionPlan {
    param([string[]]$Apps)
    foreach($name in @($Apps)){
        if($name -notin (Get-BnqqSessionAllowedApps)){throw ('Programa fora da lista admitida: '+$name)}
    }
    $result=@(foreach($name in @($Apps|Select-Object -Unique)){
        foreach($p in @(Get-Process -Name $name -ErrorAction SilentlyContinue)){
            try{$s=Get-BnqqSessionProcess $p.Id}finally{if($p -is [Diagnostics.Process]){$p.Dispose()}}
            if($s -and $s.Priority -in @('Normal','AboveNormal','High')){$s}
        }
    })
    if($result.Count -gt 128){throw 'Mais de 128 participantes: selecione menos aplicativos'}
    return $result
}
function Restore-BnqqGameSession {
    param([Parameter(Mandatory)][string]$File)
    $j=Get-Content -LiteralPath $File -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    if($j.Schema -ne 'BNQQ.Session.1' -or $j.Owner -ne (Get-BnqqOwner) -or @($j.Entries).Count -gt 128){throw 'Journal de sessao invalido ou de outro usuario'}
    # Validate all entries before any process mutation; never execute commands from a journal.
    foreach($e in @($j.Entries)){
        if($e.Name -notin (Get-BnqqSessionAllowedApps) -or $e.BeforePriority -notin @('Normal','AboveNormal','High') -or $e.AfterPriority -ne 'BelowNormal' -or $e.ProcessId -le 0 -or -not $e.StartTime){throw 'Participante/transicao de sessao invalido'}
    }
    $errors=@()
    foreach($e in @($j.Entries)){
        if($e.Status -in @('Restored','Exited')){continue}
        try {
            $live=Get-BnqqSessionProcess $e.ProcessId
            if(-not $live -or $live.StartTime -cne $e.StartTime -or $live.Name -ine $e.Name){$e.Status='Exited'}
            elseif($live.Priority -ceq $e.BeforePriority){$e.Status='Restored'}
            elseif($live.Priority -cne $e.AfterPriority){throw 'Prioridade alterada externamente; nao sobrescrever'}
            else {
                Set-BnqqSessionPriority $e.ProcessId $e.BeforePriority $live
                $after=Get-BnqqSessionProcess $e.ProcessId
                if($after -and ($after.StartTime -cne $e.StartTime -or $after.Priority -cne $e.BeforePriority)){throw 'Restauracao nao verificada'}
                $e.Status=if($after){'Restored'}else{'Exited'}
            }
        }catch{$errors+=$_.Exception.Message}
        Write-BnqqAtomicJson $j $File
    }
    $j.Status=if($errors.Count){'NeedsRecovery'}else{'Restored'}
    Write-BnqqAtomicJson $j $File
    if($errors.Count){throw ('Sessao precisa de recuperacao: '+($errors -join '; '))}
    return $j
}
function Wait-BnqqSessionGame {
    param($Identity)
    while($true){
        $live=Get-BnqqSessionProcess $Identity.ProcessId
        if(-not $live -or $live.StartTime -cne $Identity.StartTime -or $live.Name -ine $Identity.Name){return}
        Start-Sleep -Seconds 2
    }
}
function Invoke-BnqqGameSession {
    param([ValidateSet('plan','run','restore')][string]$Action='plan',[string[]]$Apps,
        [ValidateSet('cs2.exe','VALORANT-Win64-Shipping.exe')][string]$Game='cs2.exe',[string]$File)
    if($Action -eq 'plan'){
        return [pscustomobject]@{Action='Preview';Participants=@(Get-BnqqSessionPlan $Apps);TargetPriority='BelowNormal';Game=$Game;Note='Somente apps escolhidos; participantes fixos. Nao garante ganho quando nao ha concorrencia de CPU.'}
    }
    if($Action -eq 'run'){
        if(-not $Apps.Count){throw 'Escolha -SessionApps; lista vazia nunca altera aplicativos'}
        Assert-BnqqHeavyQa -WorkloadOnly
    }
    $lock=Enter-BnqqStateLock
    try {
        if($Action -eq 'restore'){return (Restore-BnqqGameSession $File)}
        Assert-BnqqNoPendingJournal
        $dir=Join-Path (Get-BnqqDataRoot) 'sessions'
        foreach($old in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)){
            $prior=Get-Content $old.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if($prior.Status -ne 'Restored'){throw ('Restaure a sessao anterior: '+$old.FullName)}
        }
        $gameProcess=@(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($Game)) -ErrorAction Stop)
        if($gameProcess.Count -ne 1){throw 'Uma unica instancia de jogo exigida'}
        try{$identity=Get-BnqqSessionProcess $gameProcess[0].Id}finally{foreach($p in $gameProcess){if($p -is [Diagnostics.Process]){$p.Dispose()}}}
        if(-not $identity){throw 'Jogo encerrou durante preparacao'}
        $participants=@(Get-BnqqSessionPlan $Apps)
        if(-not $participants.Count){return [pscustomobject]@{Status='NoParticipants';Note='Nenhuma prioridade alterada'}}
        $file=Join-Path $dir ([guid]::NewGuid().ToString('N')+'.json')
        $j=[pscustomobject]@{Schema='BNQQ.Session.1';Owner=(Get-BnqqOwner);Started=[datetime]::UtcNow.ToString('o');Game=$identity;Status='Prepared';Entries=@()}
        Write-BnqqAtomicJson $j $file
        try {
            foreach($p in $participants){
                $live=Get-BnqqSessionProcess $p.ProcessId
                if(-not $live -or -not (Test-BnqqSameValue $p $live)){throw 'Participante mudou antes da aplicacao'}
                $e=[pscustomobject]@{ProcessId=$p.ProcessId;Name=$p.Name;StartTime=$p.StartTime;BeforePriority=$p.Priority;AfterPriority='BelowNormal';Status='Prepared'}
                $j.Entries=@($j.Entries)+@($e)
                Write-BnqqAtomicJson $j $file
                Set-BnqqSessionPriority $p.ProcessId 'BelowNormal' $p
                $live=Get-BnqqSessionProcess $p.ProcessId
                if(-not $live -or $live.StartTime -cne $p.StartTime -or $live.Priority -ne 'BelowNormal'){throw 'Aplicacao de prioridade nao verificada'}
                $e.Status='Applied';Write-BnqqAtomicJson $j $file
            }
            $j.Status='Active';Write-BnqqAtomicJson $j $file
            Write-Host ('Sessao ativa; recuperacao: '+$file)
            Wait-BnqqSessionGame $identity
        }finally{Restore-BnqqGameSession $file | Out-Null}
        return [pscustomobject]@{Status='Restored';Journal=$file;Participants=$participants.Count}
    }finally{$lock.Dispose()}
}
