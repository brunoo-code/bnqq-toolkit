# Bounded, sampled background CPU placement; never touches the game's scheduling.
function Get-BnqqFocusIdentity {
    param([int]$ProcessId)
    $p=Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if(-not $p){return $null}
    try{[pscustomobject]@{ProcessId=$p.Id;Name=$p.ProcessName;StartTime=$p.StartTime.ToUniversalTime().ToString('o')}}finally{$p.Dispose()}
}
function Get-BnqqFocusStatus {
    $file=Join-Path (Get-BnqqDataRoot) 'focus-session.json'
    if(-not (Test-Path -LiteralPath $file)){return $null}
    $s=Get-Content -LiteralPath $file -Raw -ErrorAction Stop|ConvertFrom-Json
    if($s.Schema -cne 'BNQQ.Focus.1' -or $s.Owner -cne (Get-BnqqOwner)){throw 'Estado focus invalido'}
    $live=Get-BnqqFocusIdentity $s.Controller.ProcessId
    if($live -and (Test-BnqqSameValue $live $s.Controller)){return $s}
    return $null
}
function Assert-BnqqNoDynamicFocus {
    if(Get-BnqqFocusStatus){throw 'Sessao focus dinamica ativa: encerre cooperativamente antes do FrameBench. Para ensaios use participantes fixos (cpu-session).'}
}
function Stop-BnqqFocusSession {
    $s=Get-BnqqFocusStatus
    if(-not $s){return [pscustomobject]@{Status='NotRunning';Note='Nao matar processos; veja backups pendentes na recuperacao'}}
    Write-BnqqAtomicJson @{Id=$s.Id;Owner=$s.Owner} (Join-Path (Get-BnqqDataRoot) 'focus-stop.json')
    [pscustomobject]@{Status='StopRequested';Id=$s.Id;Note='Saida cooperativa com restauracao; sem encerramento forcado'}
}
function Test-BnqqFocusStop {
    param([string]$Id)
    $file=Join-Path (Get-BnqqDataRoot) 'focus-stop.json'
    if(-not (Test-Path -LiteralPath $file)){return $false}
    $s=Get-Content -LiteralPath $file -Raw -ErrorAction Stop|ConvertFrom-Json
    return ($s.Id -ceq $Id -and $s.Owner -ceq (Get-BnqqOwner))
}
function Get-BnqqFocusSamples {
    param([string[]]$Apps)
    $rows=@();$count=0
    foreach($app in @($Apps|Select-Object -Unique)){
        if($app -notin (Get-BnqqCpuAllowedApps)){throw 'Aplicativo focus nao admitido'}
        foreach($p in @(Get-Process -Name $app -ErrorAction SilentlyContinue)){
            try{
                if(++$count -gt 128){throw 'Mais de 128 processos; sessao recusada'}
                Assert-BnqqCpuProcessScope $p $p.Handle
                $rows+=@([pscustomobject]@{ProcessId=$p.Id;Name=$p.ProcessName;StartTime=$p.StartTime.ToUniversalTime().ToString('o');CpuMs=$p.TotalProcessorTime.TotalMilliseconds})
            }catch{
                if($count -gt 128){throw}
                if(-not $script:BnqqFocusSampleErrors){$script:BnqqFocusSampleErrors=@{}}
                $key=[string]$p.Id+'|'+$_.Exception.Message
                if($script:BnqqFocusSampleErrors.Count -lt 128 -and -not $script:BnqqFocusSampleErrors.ContainsKey($key)){
                    $script:BnqqFocusSampleErrors[$key]=$true;Write-BnqqNightLog 'FOCUS-SAMPLE-SKIP' $key
                }
            }
            finally{if($p -is [IDisposable]){$p.Dispose()}}
        }
    }
    return $rows
}
function Select-BnqqFocusBusy {
    param($Previous,$Current,[double]$ElapsedSeconds,[double]$MinCpuMsPerSecond=25)
    if($ElapsedSeconds -le 0 -or $ElapsedSeconds -gt 30){return @()}
    $before=@{};foreach($s in @($Previous)){$before[([string]$s.ProcessId+'|'+$s.StartTime)]=$s}
    $ranked=@(foreach($s in @($Current)){
        $key=[string]$s.ProcessId+'|'+$s.StartTime
        if(-not $before.ContainsKey($key) -or $s.Name -cne $before[$key].Name){continue}
        $delta=[double]$s.CpuMs-[double]$before[$key].CpuMs
        if($delta -ge ($MinCpuMsPerSecond*$ElapsedSeconds)){
            [pscustomobject]@{Key=$key;ProcessId=$s.ProcessId;Name=$s.Name;StartTime=$s.StartTime;RateMsPerSecond=($delta/$ElapsedSeconds)}
        }
    })
    return @($ranked|Sort-Object RateMsPerSecond -Descending)
}
function Get-BnqqFocusPlan {
    param([string[]]$Apps,[int]$BackgroundCores=2,[switch]$PauseSearch,[switch]$DeferMaintenance,[ValidateSet('CpuSets','Priority')][string]$Policy='CpuSets')
    foreach($app in @($Apps)){if($app -notin (Get-BnqqCpuAllowedApps)){throw 'Aplicativo focus nao admitido'}}
    if($Policy -eq 'Priority'){foreach($app in @($Apps)){if($app -notin (Get-BnqqBudgetAllowedApps)){throw 'Modo Priority aceita somente navegadores e OneDrive escolhidos'}}}
    $cpu=if(@($Apps).Count -and $Policy -eq 'CpuSets'){Get-BnqqCpuSessionPlan $Apps $BackgroundCores}else{[pscustomobject]@{CpuSetIds=@();Operations=@();Errors=@()}}
    $maintenance=Get-BnqqMaintenancePlan -PauseSearch:$PauseSearch -DeferMaintenance:$DeferMaintenance
    [pscustomobject]@{Status='Preview';Policy=$Policy;Apps=@($Apps);Cpu=$cpu;Maintenance=$maintenance;Limits=@{LiveProcesses=128;EntriesPerEpoch=512;Epochs=64;ChangesPerPoll=2;SampleSeconds=5;MinimumCpuMsPerSecond=25;PriorityQuietCpuMsPerSecond=5;PriorityQuietSamples=3;PriorityAdmissionCooldownSeconds=15};Note='Politica somente apos atividade medida e com o jogo em foco. Priority preserva CPU Sets/afinidades e libera o periodo apos tres amostras de baixa atividade. Sem ganho de FPS presumido.';PriorityInheritanceNote=$(if($Policy -eq 'Priority'){'Filhos novos podem herdar BelowNormal. Sem estado anterior, nao sao promovidos na restauracao; reabra o app se necessario.'})}
}
function Test-BnqqFocusQuiet {
    param($Previous,$Current,[double]$ElapsedSeconds)
    if($ElapsedSeconds -le 0 -or $ElapsedSeconds -gt 30){return $false}
    $before=@{};foreach($s in @($Previous)){$before[([string]$s.ProcessId+'|'+$s.StartTime)]=$s}
    foreach($s in @($Current)){
        $key=[string]$s.ProcessId+'|'+$s.StartTime
        # A newly observed process or counter reset is unknown, never idle proof.
        if(-not $before.ContainsKey($key) -or $s.Name -cne $before[$key].Name){return $false}
        $delta=[double]$s.CpuMs-[double]$before[$key].CpuMs
        if($delta -lt 0 -or $delta -ge 5*$ElapsedSeconds){return $false}
    }
    return $true
}
function Update-BnqqFocusEpoch {
    param($State,[string[]]$Apps,[int]$BackgroundCores,$Previous,$Current,[double]$ElapsedSeconds,[ValidateSet('CpuSets','Priority')][string]$Policy='CpuSets')
    # An epoch already owns these PID/start identities. Do not rebuild the CPU
    # topology and query every process handle again for participants we touched.
    # A reused PID has a different key and must still go through normal admission.
    $busy=@(Select-BnqqFocusBusy $Previous $Current $ElapsedSeconds|Where-Object {-not $State.Touched.ContainsKey($_.Key)})
    if(-not $busy.Count){return}
    if($Policy -eq 'Priority'){$plan=Get-BnqqBudgetPlan $busy $Apps}
    else{
        $plan=Get-BnqqCpuSessionPlan $Apps $BackgroundCores
        if(($plan.CpuSetIds -join ',') -cne ($State.CpuSetIds -join ',')){throw 'Topologia CPU mudou; restaurar sessao'}
    }
    foreach($errorText in @($plan.Errors)){Write-BnqqNightLog 'FOCUS-PLAN-SKIP' $errorText}
    $eligible=@{};foreach($p in $busy){$eligible[$p.Key]=$p}
    $ranked=@(foreach($op in $plan.Operations){
        $key=[string]$op.Before.ProcessId+'|'+$op.Before.StartTime
        if($eligible.ContainsKey($key) -and -not $State.Touched.ContainsKey($key)){
            [pscustomobject]@{Operation=$op;Key=$key;Rate=$eligible[$key].RateMsPerSecond}
        }
    })
    $candidates=@($ranked|Sort-Object Rate -Descending|Select-Object -First 2)
    foreach($candidate in $candidates){
        if(-not $State.Journal){
            if(++$State.Epochs -gt 64){throw 'Limite de 64 periodos de foco; restaurar e encerrar'}
            $State.Journal=New-BnqqJournal ('focus-'+$Policy.ToLowerInvariant()+'-epoch-v2')
            $State.Journals+=@($State.Journal.File)
        }
        if($State.Journal.Data.Entries.Count -ge 512){throw 'Limite de 512 participantes por periodo; restaurar e encerrar'}
        $candidate.Operation|Add-Member -NotePropertyName ActivityEvidence -NotePropertyValue ([pscustomobject]@{CpuMsPerSecond=$candidate.Rate;WindowSeconds=$ElapsedSeconds;ThresholdMsPerSecond=25;SampledUtc=[datetime]::UtcNow.ToString('o');FpsBenefitProven=$false})
        Invoke-BnqqJournalOperation $State.Journal $candidate.Operation
        $State.Touched[$candidate.Key]=$true;$State.Changes++
    }
}
function Restore-BnqqFocusEpoch {
    param($State)
    if($State.Journal){Restore-BnqqJournal $State.Journal.File|Out-Null;$State.Journal=$null}
    $State.Touched=@{}
}
function New-BnqqFocusClock {return [Diagnostics.Stopwatch]::StartNew()}
function Invoke-BnqqFocusSession {
    param([ValidateSet('plan','run','stop','status')][string]$Action='plan',[string[]]$Apps,
        [ValidateRange(1,16)][int]$BackgroundCores=2,[switch]$PauseSearch,[switch]$DeferMaintenance,
        [ValidateSet('cs2.exe','VALORANT-Win64-Shipping.exe')][string]$Game='cs2.exe',
        [ValidateRange(1,240)][int]$MaxMinutes=120,[ValidateSet('CpuSets','Priority')][string]$Policy='CpuSets')
    if($Action -eq 'stop'){return (Stop-BnqqFocusSession)}
    if($Action -eq 'status'){return (Get-BnqqFocusStatus)}
    $plan=Get-BnqqFocusPlan $Apps $BackgroundCores -PauseSearch:$PauseSearch -DeferMaintenance:$DeferMaintenance -Policy $Policy
    if($Action -eq 'plan'){return $plan}
    if(-not @($Apps).Count -and -not $PauseSearch -and -not $DeferMaintenance){throw 'Selecione apps ou manutencao; nenhum alvo implicito'}
    Assert-BnqqHeavyQa -WorkloadOnly
    $script:BnqqFocusSampleErrors=@{}
    if($plan.Maintenance.RequiresAdmin -and -not (Test-BnqqAdmin)){throw 'Manutencao temporaria exige administrador'}
    $gameProcesses=@(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($Game)) -ErrorAction Stop)
    try{
        if($gameProcesses.Count -ne 1){throw 'Uma instancia de jogo aberta exigida'}
        $identity=Get-BnqqFocusIdentity $gameProcesses[0].Id
    }finally{foreach($p in $gameProcesses){if($p -is [IDisposable]){$p.Dispose()}}}
    if(-not $identity){throw 'Jogo encerrou na preparacao'}
    $state=[pscustomobject]@{Journal=$null;Journals=@();Touched=@{};CpuSetIds=$plan.Cpu.CpuSetIds;Epochs=0;Changes=0}
    $maintenance=$null;$lock=$null;$controllerFile=Join-Path (Get-BnqqDataRoot) 'focus-session.json'
    $id=[guid]::NewGuid().ToString('N');$since=Get-Date;$clock=New-BnqqFocusClock;$written=$false
    try{
        $lock=Enter-BnqqStateLock;Assert-BnqqNoPendingJournal
        $lease=[pscustomobject]@{Schema='BNQQ.Focus.1';Owner=(Get-BnqqOwner);Id=$id;Controller=(Get-BnqqFocusIdentity $PID);Game=$identity;Started=[datetime]::UtcNow.ToString('o');MaxMinutes=$MaxMinutes;Policy=$Policy}
        Write-BnqqAtomicJson $lease $controllerFile;$written=$true
        if(@($plan.Maintenance.Operations).Count){
            $maintenance=New-BnqqJournal 'focus-maintenance-v2-phase4'
            foreach($op in $plan.Maintenance.Operations){Invoke-BnqqJournalOperation $maintenance $op;Assert-BnqqPhaseHealth $since}
        }
        $previous=@();$sampleTime=0.0;$nextHealth=0.0;$nextSample=0.0;$quietSamples=0;$admitAfter=0.0;$idleRestores=0
        while($clock.Elapsed.TotalMinutes -lt $MaxMinutes){
            $live=Get-BnqqFocusIdentity $identity.ProcessId
            if(-not $live -or -not (Test-BnqqSameValue $identity $live) -or (Test-BnqqFocusStop $id)){break}
            if($clock.Elapsed.TotalSeconds -ge $nextHealth){Assert-BnqqPhaseHealth $since;$nextHealth=$clock.Elapsed.TotalSeconds+10}
            if((Get-BnqqForegroundPid) -ne $identity.ProcessId){
                Restore-BnqqFocusEpoch $state;$previous=@();$nextSample=0;$quietSamples=0;$admitAfter=0.0
            }elseif(@($Apps).Count -and $clock.Elapsed.TotalSeconds -ge $nextSample){
                $current=@(Get-BnqqFocusSamples $Apps);$now=$clock.Elapsed.TotalSeconds
                if($Policy -eq 'Priority' -and $state.Journal -and (Test-BnqqFocusQuiet $previous $current ($now-$sampleTime))){$quietSamples++}else{$quietSamples=0}
                if($quietSamples -ge 3){
                    Restore-BnqqFocusEpoch $state;$quietSamples=0;$admitAfter=$now+15;$idleRestores++
                    Write-BnqqNightLog 'FOCUS-IDLE-RESTORED' ('Quiet background; admission cooldown until '+$admitAfter)
                }elseif($now -ge $admitAfter){Update-BnqqFocusEpoch $state $Apps $BackgroundCores $previous $current ($now-$sampleTime) -Policy $Policy}
                $previous=$current;$sampleTime=$now;$nextSample=$now+5
            }
            Start-Sleep -Seconds 1
        }
    }finally{
        try{Restore-BnqqFocusEpoch $state}
        finally{
            try{if($maintenance){Restore-BnqqJournal $maintenance.File|Out-Null}}
            finally{
                try{if($written){Remove-Item -LiteralPath $controllerFile -ErrorAction Stop}}
                finally{if($lock){$lock.Dispose()}}
            }
        }
    }
    [pscustomobject]@{Status='Restored';Policy=$Policy;Changes=$state.Changes;Epochs=$state.Epochs;IdleRestores=$idleRestores;CpuJournals=$state.Journals;MaintenanceJournal=$(if($maintenance){$maintenance.File});PerformanceMeasured=$false;RebootRequired=$false}
}
function Show-BnqqFocusMenu {
    Write-Host 'Focus: amostragem de CPU de apps escolhidos; restaura no Alt+Tab/saida. Manutencao opcional so durante o jogo.'
    $text=Read-Host ('Apps separados por virgula ('+((Get-BnqqCpuAllowedApps)-join ', ')+'); vazio=nenhum')
    $apps=@($text.Split(',')|ForEach-Object {$_.Trim()}|Where-Object {$_})
    $mode=Read-Host 'Politica: 1=prioridade dinamica (navegadores/OneDrive), 2=CPU Sets; outro cancela'
    if($mode -notin @('1','2')){return}
    $policy=if($mode -eq '1'){'Priority'}else{'CpuSets'}
    $pause=(Read-Host 'Parar indexador temporariamente? Digite SIM') -ceq 'SIM'
    $defer=(Read-Host 'Adiar manutencao nao ociosa temporariamente? Digite SIM') -ceq 'SIM'
    Invoke-BnqqFocusSession -Apps $apps -PauseSearch:$pause -DeferMaintenance:$defer -Policy $policy|Format-List
    $game=Read-Host 'Jogo aberto: 1=CS2, 2=Valorant; outro cancela'
    if($game -notin @('1','2')){return}
    Invoke-BnqqFocusSession -Action run -Apps $apps -PauseSearch:$pause -DeferMaintenance:$defer -Policy $policy -Game $(if($game -eq '1'){'cs2.exe'}else{'VALORANT-Win64-Shipping.exe'})|Format-List
}
