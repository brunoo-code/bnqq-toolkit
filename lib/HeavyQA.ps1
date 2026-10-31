function Test-BnqqHeavyQA {
    param([ValidateRange(10,30)][int]$Minutes=10,[ValidateRange(0,128)][int]$Threads=0,[ValidateRange(30,120)][int]$IdleTailSeconds=30)
    if(-not (Test-BnqqAdmin)){throw 'HeavyQA exige administrador para telemetria confiavel'}
    if(-not ('Bnqq.VerifiedLoad' -as [type])){Add-Type -Path (Join-Path $script:BnqqRoot 'lib\StabilityLoad.cs') -ErrorAction Stop}
    if($Threads -eq 0){$Threads=[Environment]::ProcessorCount}
    if($Threads -lt [Environment]::ProcessorCount){throw 'Atestado exige carga em todas as threads disponiveis'}
    $lock=Enter-BnqqStateLock
    $load=New-BnqqVerifiedLoad
    $file=Join-Path (Get-BnqqDataRoot) ([guid]::NewGuid().ToString('N')+'.qa.bin')
    $started=Get-Date;$fingerprint=$null;$events=@();$errorText=$null;$complete=$false;$cpuOk=$false;$ioOk=$false
    try {
        Assert-BnqqNoPendingJournal
        $fingerprint=Get-BnqqConfigurationFingerprint
        # Invalidate any previous PASS before starting, even if this run crashes.
        Write-BnqqAtomicJson @{Schema=2;Verdict='RUNNING';Generated=[datetime]::UtcNow.ToString('o')} (Join-Path (Get-BnqqDataRoot) 'heavyqa.json')
        $initial=Get-BnqqWheaEvents -Since $started
        if($initial.Error){throw $initial.Error}
        $load.Start($Threads,$file)
        $deadline=(Get-BnqqQaNow).AddMinutes($Minutes)
        while((Get-BnqqQaNow) -lt $deadline){
            Start-Sleep -Seconds 2
            $probe=Get-BnqqWheaEvents -Since $started
            if($probe.Error){throw $probe.Error}
            if(@($probe.Events).Count){$events=@($probe.Events);throw 'WHEA durante carga'}
            if($load.Failed -or -not $load.Running){throw 'Worker CPU/I/O falhou ou encerrou antes do prazo'}
        }
        $load.Stop()
        $cpuOk=$load.CpuPasses -gt 0 -and -not $load.Failed
        $ioOk=$load.IoPasses -gt 0 -and -not $load.Failed
        $deadline=(Get-BnqqQaNow).AddSeconds($IdleTailSeconds)
        while((Get-BnqqQaNow) -lt $deadline){
            Start-Sleep -Seconds 2
            $probe=Get-BnqqWheaEvents -Since $started
            if($probe.Error){throw $probe.Error}
            if(@($probe.Events).Count){$events=@($probe.Events);throw 'WHEA durante cauda idle'}
        }
        if((Get-BnqqConfigurationFingerprint) -cne $fingerprint){throw 'Configuracao mudou durante o teste'}
        $complete=$cpuOk -and $ioOk
    }catch{$errorText=$_.Exception.Message}
    finally{
        try{
            try{$load.Dispose();if(Test-Path $file){Remove-Item -LiteralPath $file -ErrorAction Stop}}
            catch{$errorText='Cleanup: '+$_.Exception.Message;$complete=$false}
            $result=[pscustomobject]@{Schema=2;Owner=(Get-BnqqOwner);Generated=[datetime]::UtcNow.ToString('o');Started=$started.ToUniversalTime().ToString('o');Fingerprint=$fingerprint;Seconds=$Minutes*60;IdleTailSeconds=$IdleTailSeconds;Threads=$Threads;CpuVerified=$cpuOk;IoVerified=$ioOk;CpuPasses=$load.CpuPasses;IoPasses=$load.IoPasses;Completed=$complete;WheaCount=$events.Count;Error=$errorText;Verdict=$(if($complete -and -not $errorText){'PASS'}else{'FAIL'});Limit='Sem erro detectado nesta carga e janela. Nao certifica estabilidade absoluta, CO, RAM ou GPU; BIOS/CO externos nao sao totalmente observaveis.'}
            Write-BnqqAtomicJson $result (Join-Path (Get-BnqqDataRoot) 'heavyqa.json')
        }finally{$lock.Dispose()}
    }
    return $result
}
function New-BnqqVerifiedLoad {return (New-Object Bnqq.VerifiedLoad)}
function Get-BnqqQaNow {return [datetime]::UtcNow}
