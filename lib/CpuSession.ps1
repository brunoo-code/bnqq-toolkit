function Initialize-BnqqCpuSets {
    if(-not ('Bnqq.CpuSets' -as [type])){Add-Type -Path (Join-Path $script:BnqqRoot 'lib\CpuSets.cs') -ErrorAction Stop}
}
function Get-BnqqCpuSetTable {Initialize-BnqqCpuSets;return @([Bnqq.CpuSets]::Enumerate())}
function Assert-BnqqCpuProcessScope {
    param($Process,[IntPtr]$Handle)
    Initialize-BnqqCpuSets
    if(-not $script:BnqqCpuScope){
        $self=[Diagnostics.Process]::GetCurrentProcess();$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
        try{$script:BnqqCpuScope=[pscustomobject]@{SessionId=$self.SessionId;Owner=$identity.User.Value}}
        finally{$self.Dispose();$identity.Dispose()}
    }
    if($Process.SessionId -ne $script:BnqqCpuScope.SessionId -or [Bnqq.CpuSets]::OwnerSid($Handle) -cne $script:BnqqCpuScope.Owner){throw 'CPU Sets recusado: processo de outro usuario/sessao'}
}
function Write-BnqqNightLog {
    param([string]$Stage,[string]$Message)
    $root=Get-BnqqDataRoot;[void][IO.Directory]::CreateDirectory($root)
    $line=('{0} [{1}] {2}' -f [datetime]::UtcNow.ToString('o'),$Stage,($Message -replace '[\r\n]+',' '))
    Add-Content -LiteralPath (Join-Path $root 'bnqq-night-log.txt') -Value $line -Encoding UTF8 -ErrorAction Stop
}
function Get-BnqqCpuBackgroundIds {
    param($Table,[ValidateRange(1,16)][int]$CoreCount=2)
    $rows=@($Table)
    if(-not $rows.Count -or @($rows|Where-Object {$_.Group -ne 0 -or $_.Logical -gt 62 -or ($_.Flags -band 2)}).Count){throw 'Topologia multigrupo/reservada nao admitida; nenhuma mascara generica'}
    if(@($rows|Select-Object -ExpandProperty Efficiency -Unique).Count -ne 1){throw 'CPU hibrida exige politica especifica'}
    if(@($rows|Select-Object -ExpandProperty Id -Unique).Count -ne $rows.Count -or @($rows|Select-Object -ExpandProperty Logical -Unique).Count -ne $rows.Count){throw 'Topologia CPU Sets duplicada'}
    $cores=@($rows|Group-Object Core|Sort-Object {[int]$_.Name})
    if($cores.Count -lt 4 -or $CoreCount -gt ($cores.Count-2)){throw 'Preserve pelo menos dois nucleos fisicos fora do grupo de background'}
    return @($cores|Select-Object -Last $CoreCount|ForEach-Object {$_.Group}|Select-Object -ExpandProperty Id|Sort-Object)
}
function Get-BnqqCpuSetProcessState {
    param([int]$ProcessId,$Expected)
    Initialize-BnqqCpuSets
    $p=Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if(-not $p){return $null}
    try {
        $handle=$p.Handle;$start=$p.StartTime.ToUniversalTime().ToString('o');$name=$p.ProcessName
        if($Expected -and ($start -cne $Expected.StartTime -or $name -ine $Expected.Name)){return $null}
        Assert-BnqqCpuProcessScope $p $handle
        return [pscustomobject]@{ProcessId=$p.Id;Name=$name;StartTime=$start;Sets=@([Bnqq.CpuSets]::Read($handle))}
    }finally{$p.Dispose()}
}
function Set-BnqqCpuSetProcessState {
    param($State,$Expected)
    if(-not $Expected){throw 'Processo encerrou antes da escrita CPU Sets'}
    Initialize-BnqqCpuSets
    $p=Get-Process -Id $State.ProcessId -ErrorAction Stop
    try {
        $handle=$p.Handle
        Assert-BnqqCpuProcessScope $p $handle
        $live=[pscustomobject]@{ProcessId=$p.Id;Name=$p.ProcessName;StartTime=$p.StartTime.ToUniversalTime().ToString('o');Sets=@([Bnqq.CpuSets]::Read($handle))}
        if(-not (Test-BnqqSameValue $live $Expected) -or $live.StartTime -cne $State.StartTime -or $live.Name -ine $State.Name){throw 'Processo/CPU Sets mudou antes da escrita'}
        $available=@(Get-BnqqCpuSetTable|Select-Object -ExpandProperty Id)
        if(@($State.Sets|Where-Object {$_ -notin $available}).Count){throw 'CPU Set deixou de existir'}
        [Bnqq.CpuSets]::Write($handle,[uint32[]]@($State.Sets))
    }finally{$p.Dispose()}
}
function Get-BnqqPhaseHealth {
    param([datetime]$Since)
    $whea=Get-BnqqWheaEvents -Since $Since
    $errorText=$whea.Error;$power=@()
    try {$power=@(Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-Kernel-Power';Id=41;StartTime=$Since} -ErrorAction Stop)}
    catch{if($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*'){$errorText=([string]$errorText+'; '+$_.Exception.Message)}}
    return [pscustomobject]@{Healthy=(-not $errorText -and -not @($whea.Events).Count -and -not $power.Count);WheaCount=@($whea.Events).Count;KernelPower41=$power.Count;Error=$errorText}
}
function Assert-BnqqPhaseHealth {
    param([datetime]$Since)
    $h=Get-BnqqPhaseHealth $Since
    if(-not $h.Healthy){throw ('Saude indeterminada/WHEA/Kernel-Power: '+($h|ConvertTo-Json -Compress))}
}
function Get-BnqqCpuSessionPlan {
    param([string[]]$Apps,[ValidateRange(1,16)][int]$BackgroundCores=2,[switch]$UnparkCpu)
    foreach($app in @($Apps)){if($app -notin (Get-BnqqCpuAllowedApps)){throw ('Aplicativo CPU nao admitido: '+$app)}}
    $table=@(Get-BnqqCpuSetTable);$ids=@(Get-BnqqCpuBackgroundIds $table $BackgroundCores)
    $ops=@();$errors=@()
    if($UnparkCpu){
        $before=Get-BnqqPowerSnapshot -Setting CPMINCORES
        if($before.AC -ne 100){$after=$before|Select-Object *;$after.AC=100;$ops+=@([pscustomobject]@{Kind='Power';Before=$before;After=$after})}
    }
    $count=0
    foreach($app in @($Apps|Select-Object -Unique)){
        foreach($p in @(Get-Process -Name $app -ErrorAction SilentlyContinue)){
            try {
                if(++$count -gt 128){throw 'Mais de 128 processos; selecione menos aplicativos'}
                $before=Get-BnqqCpuSetProcessState $p.Id
                if(-not $before){continue}
                $affinity=[int64]$p.ProcessorAffinity
                $target=@($table|Where-Object {$_.Id -in $ids -and ($affinity -band ([int64]1 -shl $_.Logical)) -ne 0}|Select-Object -ExpandProperty Id|Sort-Object)
                if(@($before.Sets).Count){$target=@($target|Where-Object {$_ -in $before.Sets})}
                if(-not $target.Count){$errors+=('Sem intersecao CPU Sets: '+$p.Id);continue}
                $after=$before|Select-Object *;$after.Sets=$target
                if(-not (Test-BnqqSameValue $before $after)){$ops+=@([pscustomobject]@{Kind='CpuSets';Before=$before;After=$after})}
            }catch{if($count -gt 128){throw};$errors+=$_.Exception.Message}
            finally{if($p -is [Diagnostics.Process]){$p.Dispose()}}
        }
    }
    return [pscustomobject]@{BackgroundCores=$BackgroundCores;CpuSetIds=$ids;Operations=$ops;Errors=$errors;Note='CPU Sets de apps escolhidos. Jogo, prioridades e afinidades rigidas preservados. Sem isolamento exclusivo de cache ou ganho presumido.'}
}
function Wait-BnqqCpuSession {
    param($Game,[datetime]$Since)
    $next=[datetime]::UtcNow
    while($true){
        $live=Get-BnqqSessionProcess $Game.ProcessId
        if(-not $live -or $live.StartTime -cne $Game.StartTime -or $live.Name -ine $Game.Name){return}
        if([datetime]::UtcNow -ge $next){Assert-BnqqPhaseHealth $Since;$next=[datetime]::UtcNow.AddSeconds(10)}
        Start-Sleep -Seconds 2
    }
}
function Invoke-BnqqCpuSession {
    param([ValidateSet('plan','run','restore')][string]$Action='plan',[string[]]$Apps,
        [ValidateRange(1,16)][int]$BackgroundCores=2,[switch]$UnparkCpu,
        [ValidateSet('cs2.exe','VALORANT-Win64-Shipping.exe')][string]$Game='cs2.exe',[string]$File)
    if($Action -eq 'plan'){return (Get-BnqqCpuSessionPlan $Apps $BackgroundCores -UnparkCpu:$UnparkCpu)}
    if($Action -eq 'restore'){return (Invoke-BnqqRecovery $File)}
    $lock=$null;$j=$null;$since=Get-Date
    try {
        if($UnparkCpu){Assert-BnqqHeavyQa}else{Assert-BnqqHeavyQa -WorkloadOnly}
        $lock=Enter-BnqqStateLock;Assert-BnqqNoPendingJournal
        $plan=Get-BnqqCpuSessionPlan $Apps $BackgroundCores -UnparkCpu:$UnparkCpu
        foreach($errorText in $plan.Errors){Write-BnqqNightLog 'CPU-SKIP' $errorText}
        if(-not @($plan.Operations).Count){return [pscustomobject]@{Status='NoChanges';Note='Nenhum alvo precisa de alteracao; nao reaplicar tweak ja ativo'}}
        if(@($plan.Operations|Where-Object Kind -eq 'Power').Count -and -not (Test-BnqqAdmin)){throw 'Alteracao de energia exige administrador'}
        $games=@(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($Game)) -ErrorAction Stop)
        try{if($games.Count -ne 1){throw 'Uma instancia do jogo exigida'};$identity=Get-BnqqSessionProcess $games[0].Id}finally{foreach($p in $games){if($p -is [Diagnostics.Process]){$p.Dispose()}}}
        if(-not $identity){throw 'Jogo encerrou na preparacao'}
        $j=New-BnqqJournal 'cpu-session-v2-phase1'
        try {
            foreach($op in @($plan.Operations)){Invoke-BnqqJournalOperation $j $op;Assert-BnqqPhaseHealth $since}
            $j.Data.Status='Applied';Write-BnqqAtomicJson $j.Data $j.File
            Write-BnqqNightLog 'CPU-ACTIVE' $j.File
            Wait-BnqqCpuSession $identity $since
        }catch{Write-BnqqNightLog 'CPU-ROLLBACK' $_.Exception.Message;throw}
        finally{Restore-BnqqJournal $j.File|Out-Null;Write-BnqqNightLog 'CPU-RESTORED' $j.File}
        return [pscustomobject]@{Status='Restored';Journal=$j.File;Operations=$plan.Operations.Count;PerformanceMeasured=$false}
    }catch{if($j){$_.Exception.Data['BnqqJournal']=$j.File};Write-BnqqNightLog 'CPU-FAILED' $_.Exception.Message;throw}
    finally{if($lock){$lock.Dispose()}}
}
function Show-BnqqCpuSessionMenu {
    Write-Host ('CPU Sets opcionais de background: '+((Get-BnqqCpuAllowedApps)-join ', '))
    $text=Read-Host 'Apps separados por virgula; vazio cancela'
    if(-not $text.Trim()){return}
    $apps=@($text.Split(',')|ForEach-Object {$_.Trim()}|Where-Object {$_})
    $plan=Invoke-BnqqCpuSession -Apps $apps
    Write-Host ('Operacoes propostas: '+@($plan.Operations).Count+'; sem alterar o jogo ou o plano de energia')
    $choice=Read-Host 'Jogo aberto: 1=CS2, 2=Valorant; outro cancela'
    if($choice -notin @('1','2')){return}
    $game=if($choice -eq '1'){'cs2.exe'}else{'VALORANT-Win64-Shipping.exe'}
    Invoke-BnqqCpuSession -Action run -Apps $apps -Game $game|Format-List
}
