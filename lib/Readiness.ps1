function Get-BnqqReadiness {
    $errors=@();$boot=$null;$historic=$null;$current=$null;$resource=$null;$strict=$null
    try{
        $boot=Get-BnqqBootUtc
        $historic=Get-BnqqWheaEvents
        $current=Get-BnqqWheaEvents -Since $boot
        if($historic.Error){$errors+=$historic.Error};if($current.Error){$errors+=$current.Error}
        $resource=Get-BnqqLatestHeavyQa -WorkloadOnly
        $strict=Get-BnqqLatestHeavyQa
    }catch{$errors+=$_.Exception.Message}
    [pscustomobject]@{Schema='BNQQ.Readiness.1';BootUtc=$boot;HistoricWhea72h=@($historic.Events).Count;CurrentBootWhea=@($current.Events).Count;
        WorkloadReady=($errors.Count -eq 0 -and $null -ne $current -and @($current.Events).Count -eq 0 -and $resource -and $resource.Passed);
        PowerClockReady=($errors.Count -eq 0 -and $null -ne $historic -and @($historic.Events).Count -eq 0 -and $strict -and $strict.Passed);
        WorkloadQa=$resource;Errors=$errors;Note='Historico preservado. Recursos reversiveis exigem QA schema 3 neste boot; energia/clocks mantem janela rigorosa de 72h.'}
}
