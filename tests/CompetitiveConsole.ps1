#Requires -Version 5.1
# Fake game, input and controller. No launch, stress or real process changes.
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\Core.ps1');. (Join-Path $root 'lib\CompetitiveConsole.ps1')
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath());$script:BnqqDataRoot=Join-Path $base ('bnqq-console-'+[guid]::NewGuid().ToString('N'))
$script:checks=0;$script:active=@();$script:choice='1';$script:ready=$true;$script:ran=0;$script:waits=0;$script:key=$null
function Check($ok,$msg){if(-not $ok){throw $msg};$script:checks++}
function Get-BnqqCompetitiveProcesses {foreach($n in $script:active){[pscustomobject]@{ProcessName=$n}}}
function Read-BnqqCompetitiveGameChoice {$script:choice}
function Wait-BnqqCompetitiveConsoleExit {$script:waits++}
function Get-BnqqCompetitiveConsoleKey {$script:key}
function Invoke-BnqqCompetitiveStart {
 param($Action='plan',$Game,$KeepApps,[switch]$LaunchGame,$MaxMinutes,$StopRequested,$SessionObserver)
 if($Action -eq 'plan'){return [pscustomobject]@{Game=$Game;CanRun=$script:ready;Apps=@('chrome');OtherOptimizers=@();BlockedReasons=@('Fixture');GameAlreadyOpen=($script:active.Count -gt 0)}}
 $script:ran++;Check $LaunchGame 'Official launch permission missing'
 Check ($MaxMinutes -eq 240 -and $KeepApps -contains 'Discord') 'Session limits/voice protection missing'
 Check ($null -ne $StopRequested -and $null -ne $SessionObserver) 'Interactive controls missing'
 $script:key='Q';Check (&$StopRequested) 'Q does not request cooperative stop'
 &$SessionObserver ([pscustomobject]@{Phase='Desktop';TrackedParticipants=0;Changes=2})
 [pscustomobject]@{Status='Restored';Changes=2;PerformanceMeasured=$false}
}
try{
 $r=Show-BnqqCompetitiveConsole -DryRun;Check ($r.Status -eq 'SelectGame' -and $script:ran -eq 0) 'Dry run prompted or ran a session'
 $script:active=@('VALORANT-Win64-Shipping');$r=Show-BnqqCompetitiveConsole -DryRun
 Check ($r.Game -eq 'VALORANT-Win64-Shipping.exe') 'Open game not detected'
 $r=Show-BnqqCompetitiveConsole -Game cs2.exe -DryRun;Check ($r.Game -eq 'cs2.exe') 'Explicit game ignored'
 $script:ready=$false;Show-BnqqCompetitiveConsole|Out-Null;Check ($script:ran -eq 0 -and $script:waits -eq 1) 'Blocked session executed or lost explanation'
 $script:ready=$true;Show-BnqqCompetitiveConsole|Out-Null
 Check ($script:ran -eq 1 -and @(Get-ChildItem (Join-Path $script:BnqqDataRoot 'competitive-reports') -Filter '*.json').Count -eq 1) 'Auto-attach/report not produced'
 $report=Get-Content (Get-ChildItem (Join-Path $script:BnqqDataRoot 'competitive-reports') -Filter '*.json'|Select-Object -First 1).FullName -Raw|ConvertFrom-Json
 Check ($report.Result.Status -eq 'Restored' -and -not $report.FpsGainMeasured) 'Report invented a performance gain'
 foreach($k in @('Q','Escape')){$script:key=$k;Check (Test-BnqqCompetitiveConsoleStop) 'Stop key rejected'}
 foreach($k in @('A',$null)){$script:key=$k;Check (-not (Test-BnqqCompetitiveConsoleStop)) 'Unrelated key stopped session'}
 $script:active=@();$script:choice='Q';Show-BnqqCompetitiveConsole|Out-Null;Check ($script:ran -eq 1) 'Cancel selection launched game'
 "PASS: competitive console $script:checks checks; auto-detection, explicit selection, readiness refusal, cooperative keys, observer and honest report"
}finally{
 $full=[IO.Path]::GetFullPath($script:BnqqDataRoot);if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $full -Leaf) -notlike 'bnqq-console-*'){throw 'Unsafe fixture cleanup'}
 if([IO.Directory]::Exists($full)){[IO.Directory]::Delete($full,$true)}
}
