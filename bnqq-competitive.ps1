#Requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('','cs2.exe','VALORANT-Win64-Shipping.exe')][string]$FrameProcess='',[string[]]$KeepApps=@('Discord','Spotify'),[ValidateRange(1,240)][int]$SessionMinutes=240,[switch]$DryRun,[switch]$StopSession)
$ErrorActionPreference='Stop';$script:BnqqRoot=$PSScriptRoot
foreach($n in @('Core','Governance','Readiness','RuntimeLatency','CpuSession','ProcessSampling','BackgroundBudget','Maintenance','NetworkSession','FocusSession','CompetitiveStart','CompetitiveConsole')){. (Join-Path $script:BnqqRoot ('lib\'+$n+'.ps1'))}
if($StopSession){if($DryRun){[pscustomobject]@{Status='Preview';WouldStop=$true}|ConvertTo-Json}else{Invoke-BnqqCompetitiveStart -Action stop|Format-List};return}
if($DryRun){Show-BnqqCompetitiveConsole -Game $FrameProcess -KeepApps $KeepApps -MaxMinutes $SessionMinutes -DryRun|ConvertTo-Json -Depth 10}
else{Show-BnqqCompetitiveConsole -Game $FrameProcess -KeepApps $KeepApps -MaxMinutes $SessionMinutes}
