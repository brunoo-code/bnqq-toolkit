function Start-BnqqWatcher {
    param([ValidateRange(1,30)][int]$IntervalSeconds=2,[switch]$PinPhysical,[switch]$AboveNormal,[switch]$ObserveWmi,[switch]$Once)
    $mutating=$PinPhysical -or $AboveNormal
    if($mutating){Assert-BnqqHeavyQa}
    $lock=Enter-BnqqStateLock
    $journal=$null;$activeId=$null;$observer=$false;$wmiError=$null
    $stopFile=Join-Path (Get-BnqqDataRoot) 'watcher.stop'
    $heartbeat=Join-Path (Get-BnqqDataRoot) 'watcher.json'
    try {
        Assert-BnqqNoPendingJournal
        if(Test-Path $stopFile){Remove-Item -LiteralPath $stopFile -ErrorAction Stop}
        if($ObserveWmi){
            try{
                if(-not ('BnqqProcessLasso' -as [type])){Add-Type -Path (Join-Path $script:BnqqRoot 'lib\BnqqProcessLasso.cs') -ReferencedAssemblies System.Management -ErrorAction Stop}
                $observer=[BnqqProcessLasso]::Start()
            }catch{$wmiError=$_.Exception.Message;Write-Warning ('Observador WMI indisponivel; mantendo observacao basica: '+$wmiError)}
        }
        Write-Host 'Watcher: observacao por padrao. Sem standby purge, clock lock, timer request, suspensao ou afinidade de background.'
        do {
            $fg=Get-BnqqForegroundPid
            $game=Get-Process -Id $fg -ErrorAction SilentlyContinue | Where-Object {$_.ProcessName -in @('cs2','VALORANT-Win64-Shipping')}
            if($journal -and (-not $game -or $game.Id -ne $activeId)){
                Restore-BnqqJournal $journal.File | Out-Null
                $journal=$null;$activeId=$null
            }
            if($mutating -and $game -and -not $journal){
                Assert-BnqqHeavyQa
                $op=New-BnqqRuntimeOperation $game.Id -PinPhysical:$PinPhysical -AboveNormal:$AboveNormal
                $journal=New-BnqqJournal 'runtime';$activeId=$game.Id
                Invoke-BnqqJournalOperation $journal $op
            }
            if($journal){Assert-BnqqWheaBaseline}
            $counters=$null
            if($observer){$counters=[BnqqProcessLasso]::Counters(); [void][BnqqProcessLasso]::Drain()}
            Write-BnqqAtomicJson ([pscustomobject]@{Schema=2;ProcessId=$PID;StartTime=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');Heartbeat=[datetime]::UtcNow.ToString('o');Mutating=[bool]$mutating;GamePid=$(if($game){$game.Id}else{$null});Journal=$(if($journal){$journal.File}else{$null});WmiCounters=$counters;WmiError=$wmiError}) $heartbeat
            if($Once -or (Test-Path $stopFile)){break}
            Start-Sleep -Seconds $IntervalSeconds
        }while($true)
    }finally{
        try{
            if($observer){[BnqqProcessLasso]::Stop()}
        }finally{
            try{if($journal){Restore-BnqqJournal $journal.File | Out-Null}}
            finally{
                if(Test-Path $heartbeat){Remove-Item -LiteralPath $heartbeat -ErrorAction SilentlyContinue}
                $lock.Dispose()
            }
        }
    }
}
function Stop-BnqqWatcher {
    $file=Join-Path (Get-BnqqDataRoot) 'watcher.json'
    if(-not (Test-Path $file)){throw 'Sem heartbeat v2; nao encerrar watcher legado a forca. Veja MIGRATION.md.'}
    $state=Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json
    $proc=Get-Process -Id $state.ProcessId -ErrorAction SilentlyContinue
    if(-not $proc -or $proc.StartTime.ToUniversalTime().ToString('o') -ne $state.StartTime){throw 'Heartbeat obsoleto; recuperar journal se necessario'}
    Write-BnqqAtomicJson @{Requested=[datetime]::UtcNow.ToString('o')} (Join-Path (Get-BnqqDataRoot) 'watcher.stop')
    $until=[datetime]::UtcNow.AddSeconds(40)
    while((Test-Path $file) -and [datetime]::UtcNow -lt $until){Start-Sleep -Milliseconds 250}
    if(Test-Path $file){throw 'Saida cooperativa nao confirmada; nao foi usado Stop-Process -Force'}
}
