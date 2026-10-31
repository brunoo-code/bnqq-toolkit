$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\FrameBench.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-gates-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
 $files=@(0..5|ForEach-Object {Join-Path $temp ($_.ToString()+'.json')})
 function Fixtures([string]$Regression=''){
  for($i=0;$i -lt 6;$i++){
   $candidate=$i%2 -eq 1
   $stats=[ordered]@{Schema=2;AvgFps=200;Low1Fps=100;Low01Fps=80;P99Ms=$(if($candidate){8}else{10});P999Ms=15;JitterMs=2;StuttersPerMinute=0;Frames=12000;DurationSeconds=60;Metric='MsBetweenPresents';Runtime='Other';SkipSeconds=5}
   if($candidate -and $Regression){$stats[$Regression]=switch($Regression){'Low1Fps'{50}'Low01Fps'{20}'JitterMs'{4}'StuttersPerMinute'{2}}}
   @{Schema=2;Variant=$(if($candidate){'candidate'}else{'baseline'});Started=([datetime]'2026-01-01').AddMinutes($i).ToString('o');Context=@{Scenario='fixture';SettingsHash='controlled'};PresentMonHash='same';Stats=$stats} | ConvertTo-Json -Depth 5 | Set-Content $files[$i] -Encoding utf8
  }
 }
 Fixtures
 if((Compare-BnqqFrameBench $files).Effective -ne $true){throw 'Controlled p99 advantage should pass'}
 foreach($metric in @('Low1Fps','Low01Fps','JitterMs','StuttersPerMinute')){
  Fixtures $metric
  $r=Compare-BnqqFrameBench $files
  if($r.Effective -eq $true -or $r.Gates.$metric){throw ('False improvement accepted despite '+$metric)}
 }
 'PASS: p99 improvement cannot hide 1%, 0.1%, jitter or stutter regression'
}finally{[IO.Directory]::Delete($temp,$true)}
