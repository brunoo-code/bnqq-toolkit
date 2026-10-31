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
    if($State.ProcessId -le 0 -or $State.ProcessId -ne $Expected.ProcessId -or $State.Name -notin (Get-BnqqBudgetAllowedApps) -or $State.Name -ine $Expected.Name -or -not $State.StartTime -or $State.StartTime -cne $Expected.StartTime){throw 'Identidade de prioridade invalida'}
    if($State.Priority -notin @('Normal','AboveNormal','High','BelowNormal') -or $Expected.Priority -notin @('Normal','AboveNormal','High','BelowNormal')){throw 'Prioridade fora da politica'}
    Set-BnqqPriorityNative -State $State -Expected $Expected
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
