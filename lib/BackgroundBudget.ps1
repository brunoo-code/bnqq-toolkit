# Dynamic CPU priority policy. No game, voice, peripheral or system targets.
function Get-BnqqBudgetAllowedApps {return @('msedge','chrome','firefox','OneDrive')}
function Get-BnqqBudgetState {
    param([int]$ProcessId,$Expected)
    if($Expected -and $Expected.ProcessId -ne $ProcessId){return $null}
    $s=Get-BnqqPriorityProbe -ProcessId $ProcessId -Expected $Expected
    if(-not $s){return $null}
    if($s.Name -notin (Get-BnqqBudgetAllowedApps)){throw 'Alvo de prioridade nao admitido'}
    if($s.ProcessId -ne $ProcessId -or ($Expected -and ($Expected.ProcessId -ne $ProcessId -or $s.Name -ine $Expected.Name -or $s.StartTime -cne $Expected.StartTime))){return $null}
    [pscustomobject]@{ProcessId=$s.ProcessId;Name=$s.Name;StartTime=$s.StartTime;Priority=$s.Priority}
}
function Set-BnqqBudgetState {
    param($State,$Expected)
    if(-not $Expected){throw 'Processo encerrou antes da escrita de prioridade'}
    $p=Get-Process -Id $State.ProcessId -ErrorAction Stop
    try {
        $handle=$p.Handle
        Assert-BnqqCpuProcessScope $p $handle
        $live=[pscustomobject]@{ProcessId=$p.Id;Name=$p.ProcessName;StartTime=$p.StartTime.ToUniversalTime().ToString('o');Priority=$p.PriorityClass.ToString()}
        if($live.Name -notin (Get-BnqqBudgetAllowedApps) -or $live.StartTime -cne $State.StartTime -or $live.Name -ine $State.Name -or -not (Test-BnqqSameValue $live $Expected)){throw 'Identidade/prioridade mudou antes da escrita'}
        if($State.Priority -notin @('Normal','AboveNormal','High','BelowNormal')){throw 'Prioridade de destino nao admitida'}
        $p.PriorityClass=$State.Priority
    }finally{$p.Dispose()}
}
function Get-BnqqBudgetPlan {
    param($Busy,[string[]]$Apps,[ValidateRange(1,128)][int]$MaxOperations=128)
    foreach($app in @($Apps)){if($app -notin (Get-BnqqBudgetAllowedApps)){throw 'Modo Priority aceita somente navegadores e OneDrive escolhidos'}}
    $ops=@();$errors=@()
    if(@($Busy).Count -gt 128){throw 'Limite de 128 participantes de prioridade'}
    foreach($sample in @($Busy)){
        if($sample.Name -notin $Apps -or $sample.Name -notin (Get-BnqqBudgetAllowedApps)){throw 'Amostra de prioridade fora da selecao'}
    }
    foreach($sample in @($Busy)){
        try {
            $before=Get-BnqqBudgetState $sample.ProcessId $sample
            if(-not $before -or $before.Priority -notin @('Normal','AboveNormal','High')){continue}
            $after=$before|Select-Object *;$after.Priority='BelowNormal'
            $ops+=@([pscustomobject]@{Kind='BackgroundPriority';Before=$before;After=$after})
            if($ops.Count -ge $MaxOperations){break}
        }catch{$errors+=('PID '+$sample.ProcessId+': '+$_.Exception.Message)}
    }
    [pscustomobject]@{Operations=$ops;Errors=$errors}
}
