#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\DpcAnalysis.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-dpc-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$csv=Join-Path $temp 'events.csv';$metadata=Join-Path $temp 'metadata.json';$script:checks=0
function Check($ok,$text){if(-not $ok){throw $text};$script:checks++}
function MustThrow([scriptblock]$Code){$hit=$false;try{& $Code|Out-Null}catch{$hit=$true};Check $hit 'Expected DPC refusal'}
function Fixture([string]$Rows){
 @('StartSeconds,DurationUs,CpuIndex,Module,Kind',$Rows)|Set-Content -LiteralPath $csv -Encoding utf8
 $script:m=[ordered]@{Schema='BNQQ.DpcCsv.1';Aggregation='IndividualEvents';TimestampUnit='seconds';DurationUnit='microseconds';DurationSemantics='InclusiveWallTime';Clock='QPC';CsvSha256=(Get-FileHash $csv).Hash;LostEvents=0;LogicalProcessorCount=2;WindowStartSeconds=1;WindowDurationSeconds=1}
 SaveMeta
}
function SaveMeta {$script:m|ConvertTo-Json|Set-Content -LiteralPath $metadata -Encoding utf8}
try {
 Fixture "1.1,1000,0,net.sys,DPC`n1.1005,1000,0,net.sys,ISR`n1.1,1000,1,ndis.sys,DPC`n0.9999,200,0,edge.sys,DPC`n3,10,0,out.sys,DPC"
 $r=Get-BnqqDpcReport $csv $metadata
 Check ($r.InputRows -eq 5 -and $r.WindowEvents -eq 4 -and $r.OutsideWindow -eq 1 -and $r.BoundaryClippedEvents -eq 1) 'Window filtering/clipping failed'
 Check ([math]::Abs($r.PerCpu[0].CoveredIntervalMs-1.6) -lt .000001) 'Overlapping DPC/ISR double counted'
 Check ([math]::Abs($r.WindowCoveragePercent-.13) -lt .000001) 'CPU/window normalization failed'
 $edge=@($r.Modules|Where-Object Module -eq 'edge.sys')[0]
 Check ($edge.FullDurationEvents -eq 0 -and $null -eq $edge.P99FullDurationUs) 'Clipped duration polluted tails'
 $net=@($r.Modules|Where-Object { $_.Module -eq 'net.sys' -and $_.Kind -eq 'DPC'})[0]
 Check ($net.P99FullDurationUs -eq 1000) 'Microseconds converted incorrectly'
 Check (@($r.Modules|Where-Object Module -eq 'ndis.sys')[0].Attribution -eq 'FrameworkOrUnknownNeedsStack') 'Framework became hardware blame'
 $m.LostEvents=1;SaveMeta;MustThrow {Get-BnqqDpcReport $csv $metadata}
 $m.LostEvents=$null;SaveMeta;MustThrow {Get-BnqqDpcReport $csv $metadata}
 $m.LostEvents=0;$m.Clock='SystemTime';SaveMeta;MustThrow {Get-BnqqDpcReport $csv $metadata}
 $m.Clock='QPC';$m.Aggregation='GroupedSummary';SaveMeta;MustThrow {Get-BnqqDpcReport $csv $metadata}
 $m.Aggregation='IndividualEvents';$m.CsvSha256=('0'*64);SaveMeta;MustThrow {Get-BnqqDpcReport $csv $metadata}
 foreach($bad in @('1.1,NaN,0,net.sys,DPC','1.1,-1,0,net.sys,DPC','1.1,1e-300,0,net.sys,DPC','1.1,10,2,net.sys,DPC','1.1,10,0,evil.ps1,DPC','1.1,10,0,net.sys,Unknown',"1.1,10,0,net.sys,DPC`n1.1,10,0,NET.SYS,DPC",'3,10,0,net.sys,DPC')){
  Fixture $bad;MustThrow {Get-BnqqDpcReport $csv $metadata}
 }
 Fixture '1.1,100,0,[unknown],ISR'
 Check ((Get-BnqqDpcReport $csv $metadata).Modules[0].Attribution -eq 'FrameworkOrUnknownNeedsStack') 'Unknown module assigned blame'
 $m.WindowStartSeconds='Infinity';SaveMeta;MustThrow {Get-BnqqDpcReport $csv $metadata}
 Fixture '1.1,100,0,net.sys,DPC'
 $m.WindowDurationSeconds=0;SaveMeta;MustThrow {Get-BnqqDpcReport $csv $metadata}
 Fixture '1.1,100,0,net.sys,DPC'
 $s=[IO.File]::OpenWrite($csv);try{$s.SetLength(17MB)}finally{$s.Dispose()}
 MustThrow {Get-BnqqDpcReport $csv $metadata}
 Check ([math]::Abs((Get-BnqqDpcUnionSeconds @(@{Start=1;End=4},@{Start=2;End=3},@{Start=4;End=5},@{Start=7;End=8}))-5) -lt .000001) 'Nested/adjacent intervals failed'
 ('PASS: offline DPC '+$script:checks+' checks; overlap, CPU denominator, clipped tails, hashes, loss, limits and invalid inputs')
}finally{if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}}
