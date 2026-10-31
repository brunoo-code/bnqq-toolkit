function Get-BnqqCatalog { return @(Get-BnqqRegistryTargets) }
function Invoke-BnqqApply {
    param([ValidateSet('recording-off','latency')][string]$Profile='recording-off',[switch]$DryRun,[switch]$ForceDeepIdleDisable)
    if($Profile -eq 'latency' -and -not $ForceDeepIdleDisable){
        Show-BnqqDisplayGuidance
        Write-Host 'Nenhuma energia/registro alterado. IDLEDISABLE exige -ForceDeepIdleDisable e HeavyQA.'
        return
    }
    if($Profile -eq 'recording-off'){
        # A documented policy is still not a proof of runtime effect on every build.
        # The local Windows policy definition must advertise this exact target.
        if(-not $DryRun){Assert-BnqqRecordingCapability}
        $t=Get-BnqqRegistryTargets | Select-Object -First 1
        $before=Get-RegSnapshot $t.Path $t.Name
        $after=[pscustomobject]@{Path=$t.Path;Name=$t.Name;KeyExisted=$true;Existed=$true;Kind=$t.Type;Value=$t.Value}
        # KeyExisted refers to the original leaf, and must match the state after writing.
        $op=[pscustomobject]@{Kind='Registry';Before=$before;After=$after}
    } else {
        $before=Get-BnqqPowerSnapshot
        $after=$before | Select-Object *
        $after.AC=1 # DC, boost policy, coalescing and resiliency are never changed.
        $op=[pscustomobject]@{Kind='Power';Before=$before;After=$after}
    }
    if($DryRun){return $op}
    if(-not (Test-BnqqAdmin)){throw 'Aplicacao exige administrador; nenhum auto-elevate silencioso'}
    Assert-BnqqHeavyQa
    $lock=Enter-BnqqStateLock
    try {
        Assert-BnqqNoPendingJournal
        $j=New-BnqqJournal $Profile
        try{Invoke-BnqqJournalOperation $j $op; $j.Data.Status='Applied'; Write-BnqqAtomicJson $j.Data $j.File}
        catch{ $original=$_; try{Restore-BnqqJournal $j.File | Out-Null}catch{Write-Warning $_};throw $original }
        Write-Host ('Aplicado e verificado; restauracao: '+$j.File)
        Write-Host 'Efeito de desempenho ainda nao demonstrado. Compare baseline controlado.'
    }finally{$lock.Dispose()}
}
function Assert-BnqqRecordingCapability {
    $file=Join-Path $env:WINDIR 'PolicyDefinitions\GameDVR.admx'
    if(-not (Test-Path -LiteralPath $file)){throw 'Definicao local GameDVR indisponivel; nao presumir suporte'}
    [xml]$xml=Get-Content -LiteralPath $file -Raw -ErrorAction Stop
    $policy=$xml.SelectSingleNode("//*[local-name()='policy' and @name='AllowGameDVR']")
    if(-not $policy -or $policy.key -ne 'Software\Policies\Microsoft\Windows\GameDVR' -or $policy.valueName -ne 'AllowGameDVR'){throw 'Definicao local diverge do alvo auditado'}
}
