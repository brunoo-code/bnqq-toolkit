# Offline normalized event analysis. Never starts ETW or executes input contents.
function Get-BnqqDpcImportContract {
    [pscustomobject]@{
        Schema='BNQQ.DpcCsv.1';Columns=@('StartSeconds','DurationUs','CpuIndex','Module','Kind')
        Metadata=@{Schema='BNQQ.DpcCsv.1';Aggregation='IndividualEvents';TimestampUnit='seconds';DurationUnit='microseconds';DurationSemantics='InclusiveWallTime';Clock='QPC';CsvSha256='REQUIRED_ACTUAL_SHA256';LostEvents=0;LogicalProcessorCount='REQUIRED_CAPTURED_CPU_COUNT';WindowStartSeconds=0;WindowDurationSeconds=60}
        Note='Normalized individual events plus JSON metadata; not a direct importer of arbitrary WPA CSV/ETL. Missing/unknown loss data is refused. No recording started.'
    }
}
function Convert-BnqqDpcNumber {
    param($Value)
    $n=[double]0
    if(-not [double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$n) -or [double]::IsNaN($n) -or [double]::IsInfinity($n)){throw 'Numero DPC ausente/nao finito'}
    return $n
}
function Get-BnqqDpcUnionSeconds {
    param($Intervals)
    $ordered=@($Intervals|Sort-Object @{Expression={[double]$_.Start}},@{Expression={[double]$_.End}})
    if(-not $ordered.Count){return 0.0}
    $total=0.0;$start=[double]$ordered[0].Start;$end=[double]$ordered[0].End
    foreach($i in @($ordered|Select-Object -Skip 1)){
        if($i.Start -le $end){$end=[math]::Max($end,$i.End)}
        else{$total+=($end-$start);$start=$i.Start;$end=$i.End}
    }
    return ($total+$end-$start)
}
function Get-BnqqDpcReport {
    param([Parameter(Mandatory)][string]$Csv,[Parameter(Mandatory)][string]$Metadata)
    $csvItem=Get-Item -LiteralPath $Csv -ErrorAction Stop
    $metaItem=Get-Item -LiteralPath $Metadata -ErrorAction Stop
    if($csvItem.PSIsContainer -or $metaItem.PSIsContainer -or $csvItem.Length -gt 16MB -or $metaItem.Length -gt 32KB){throw 'Arquivos DPC fora dos limites (CSV 16 MiB, metadata 32 KiB)'}
    $hash=(Get-FileHash -LiteralPath $Csv -Algorithm SHA256 -ErrorAction Stop).Hash
    $metaHash=(Get-FileHash -LiteralPath $Metadata -Algorithm SHA256 -ErrorAction Stop).Hash
    $m=Get-Content -LiteralPath $Metadata -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json
    if($m.Schema -cne 'BNQQ.DpcCsv.1' -or $m.Aggregation -cne 'IndividualEvents' -or $m.TimestampUnit -cne 'seconds' -or $m.DurationUnit -cne 'microseconds' -or $m.DurationSemantics -cne 'InclusiveWallTime' -or $m.Clock -cne 'QPC' -or $m.CsvSha256 -cne $hash){throw 'Schema/unidades/relogio/hash DPC nao admitidos'}
    if($null -eq $m.LostEvents -or [string]$m.LostEvents -cne '0'){throw 'Eventos perdidos ou quantidade desconhecida: analise recusada'}
    $windowStart=Convert-BnqqDpcNumber $m.WindowStartSeconds;$duration=Convert-BnqqDpcNumber $m.WindowDurationSeconds
    if($windowStart -lt 0 -or $windowStart -gt 604800 -or $duration -lt 1 -or $duration -gt 300){throw 'Janela DPC deve ter de 1 a 300 segundos, em trace de ate sete dias'}
    if([string]$m.LogicalProcessorCount -notmatch '^\d{1,4}$' -or [int]$m.LogicalProcessorCount -lt 1 -or [int]$m.LogicalProcessorCount -gt 4096){throw 'Contagem de CPUs capturadas invalida'}
    $cpuCount=[int]$m.LogicalProcessorCount;$windowEnd=$windowStart+$duration
    $events=New-Object 'Collections.Generic.List[object]';$rows=0;$outside=0;$clipped=0;$seen=New-Object 'Collections.Generic.HashSet[string]'
    Import-Csv -LiteralPath $Csv -Encoding UTF8 -ErrorAction Stop|ForEach-Object {
        $r=$_
        if(++$rows -gt 100000){throw 'Mais de 100000 eventos; selecione janela menor'}
        if($rows -eq 1){
            $names=@($r.PSObject.Properties.Name)
            if($names.Count -ne 5 -or @(@('StartSeconds','DurationUs','CpuIndex','Module','Kind')|Where-Object {$_ -notin $names}).Count){throw 'CSV exige StartSeconds,DurationUs,CpuIndex,Module,Kind; export agregado nao e aceito'}
        }
        $start=Convert-BnqqDpcNumber $r.StartSeconds;$us=Convert-BnqqDpcNumber $r.DurationUs
        if($start -lt 0 -or $start -gt 604800 -or $us -le 0 -or $us -gt 300000000 -or [string]$r.CpuIndex -notmatch '^\d{1,4}$' -or [int]$r.CpuIndex -ge $cpuCount -or $r.Kind -cnotin @('DPC','ISR')){throw 'Evento DPC invalido'}
        $module=[string]$r.Module
        if($module.Length -gt 128 -or $module -notmatch '^[a-zA-Z0-9_.-]+\.(sys|exe)$'){
            if($module -cne '[unknown]'){throw 'Modulo invalido: use nome de arquivo ou [unknown], sem caminhos/comandos'}
        }
        $module=$module.ToLowerInvariant();$end=$start+$us/1000000.0
        if($end -le $start){throw 'Duracao menor que a precisao temporal representavel'}
        $key=([string]$r.CpuIndex+'|'+$start.ToString('R',[Globalization.CultureInfo]::InvariantCulture)+'|'+$us.ToString('R',[Globalization.CultureInfo]::InvariantCulture)+'|'+$module+'|'+$r.Kind)
        if(-not $seen.Add($key)){throw 'Evento duplicado; recuse exportacoes sobrepostas'}
        if($end -le $windowStart -or $start -ge $windowEnd){$outside++}
        else{
            $left=[math]::Max($windowStart,$start);$right=[math]::Min($windowEnd,$end)
            if($left -ne $start -or $right -ne $end){$clipped++}
            $isClipped=($left -ne $start -or $right -ne $end)
            $measuredUs=if($isClipped){($right-$left)*1000000.0}else{$us}
            $events.Add([pscustomobject]@{Start=$left;End=$right;DurationUs=$measuredUs;Cpu=[int]$r.CpuIndex;Module=$module;Kind=$r.Kind;BoundaryClipped=$isClipped})
        }
    }
    if(-not $events.Count){throw 'Nenhum evento valido na janela; nao inferir latencia zero'}
    if((Get-FileHash -LiteralPath $Csv -Algorithm SHA256).Hash -cne $hash -or (Get-FileHash -LiteralPath $Metadata -Algorithm SHA256).Hash -cne $metaHash){throw 'Entrada DPC mudou durante a leitura'}
    $groups=@(foreach($g in @($events|Group-Object Module,Kind)){
        # Full-event tails exclude boundary-clipped events, whose durations are censored.
        $full=@($g.Group|Where-Object {-not $_.BoundaryClipped})
        $sorted=[double[]]@($full|Select-Object -ExpandProperty DurationUs|Sort-Object)
        $framework=$g.Group[0].Module -in @('ndis.sys','wdf01000.sys','dxgkrnl.sys','storport.sys','ntoskrnl.exe','[unknown]')
        [pscustomobject]@{
            Module=$g.Group[0].Module;Kind=$g.Group[0].Kind;Events=$g.Count;EventsPerSecond=($g.Count/$duration);FullDurationEvents=$full.Count
            CoveredEventDurationMs=($g.Group|Measure-Object DurationUs -Sum).Sum/1000.0
            MaxFullDurationUs=$(if($sorted.Count){$sorted[-1]}else{$null})
            P99FullDurationUs=$(if($sorted.Count){$sorted[[math]::Ceiling(.99*$sorted.Length)-1]}else{$null})
            Attribution=$(if($framework){'FrameworkOrUnknownNeedsStack'}else{'ModuleObservedNotRootCause'})
        }
    })
    $cpus=@(foreach($g in @($events|Group-Object Cpu)){
        $seconds=Get-BnqqDpcUnionSeconds $g.Group
        [pscustomobject]@{CpuIndex=[int]$g.Name;Events=$g.Count;CoveredIntervalMs=$seconds*1000.0;CoveredWindowPercent=100*$seconds/$duration}
    })
    [pscustomobject]@{
        Schema='BNQQ.DpcReport.1';CsvSha256=$hash;MetadataSha256=$metaHash;WindowStartSeconds=$windowStart;WindowDurationSeconds=$duration;LogicalProcessorCount=$cpuCount
        InputRows=$rows;WindowEvents=$events.Count;OutsideWindow=$outside;BoundaryClippedEvents=$clipped;LostEventsReported=0
        Modules=@($groups|Sort-Object CoveredEventDurationMs -Descending);PerCpu=@($cpus|Sort-Object CpuIndex)
        WindowCoveragePercent=100*($cpus|Measure-Object CoveredIntervalMs -Sum).Sum/(1000*$duration*$cpuCount)
        Provenance='Caller-supplied normalized export and metadata; ETL origin/loss count are not independently verified'
        Claim='Recorded event durations, not input latency, ISR-to-DPC queue delay, frametime correlation or a device-disable recommendation. Overlaps merged per CPU for coverage; module totals may overlap.'
    }
}
