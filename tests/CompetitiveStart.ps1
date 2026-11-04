#Requires -Version 5.1
# All process/launcher/controller adapters mocked; never launches games or edits process state.
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\Core.ps1');. (Join-Path $root 'lib\CompetitiveStart.ps1')
$script:checks=0;$script:ready=$true;$script:others=@();$script:running=$true;$script:focus=$null;$script:launched=0;$script:controlled=0;$script:guardFails=$false
$script:BnqqDataRoot=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-start-test-'+[guid]::NewGuid().ToString('N'))
function Check($ok,$msg){if(-not $ok){throw $msg};$script:checks++}
function MustThrow([scriptblock]$s){$hit=$false;try{&$s|Out-Null}catch{$hit=$true};Check $hit 'Expected competitive-start refusal'}
function Get-BnqqBudgetAllowedApps {@('msedge','chrome','firefox','OneDrive')}
function Get-BnqqCompetitiveProcesses {if($script:running){[pscustomobject]@{ProcessName='VALORANT-Win64-Shipping';Id=100}};[pscustomobject]@{ProcessName='chrome';Id=101};[pscustomobject]@{ProcessName='Discord';Id=102};[pscustomobject]@{ProcessName='Spotify';Id=103};[pscustomobject]@{ProcessName='vgc';Id=104}}
function Get-BnqqOtherOptimizers {$script:others}
function Get-BnqqReadiness {[pscustomobject]@{WorkloadReady=$script:ready}}
function Get-BnqqFocusStatus {$script:focus}
function Get-BnqqFocusPlan {param($Apps,$Policy,$BackgroundCores);[pscustomobject]@{Apps=$Apps;Policy=$Policy;Cores=$BackgroundCores}}
function Assert-BnqqHeavyQa {param([switch]$WorkloadOnly);if(-not $WorkloadOnly -or -not $script:ready){throw 'QA unavailable'}}
function Start-BnqqCompetitiveGame {param($Game);$script:launched++;$script:running=$true}
function Get-Process {param($Name,$ErrorAction);if($script:running){[pscustomobject]@{ProcessName='VALORANT-Win64-Shipping'}}}
function Invoke-BnqqFocusSession {param($Action,$Apps,$Policy,$BackgroundCores,$Game,$MaxMinutes,$SessionGuard);if($script:guardFails){$script:others=@([pscustomobject]@{ProcessName='PRACC Performance';Id=400})};&$SessionGuard;$script:controlled++;[pscustomobject]@{Apps=$Apps;Policy=$Policy;Game=$Game;Minutes=$MaxMinutes;Cores=$BackgroundCores}}
function Stop-BnqqFocusSession {[pscustomobject]@{Status='StopRequested'}}
$p=Invoke-BnqqCompetitiveStart -Game VALORANT-Win64-Shipping.exe -KeepApps chrome
Check ($p.CanRun -and $p.GameAlreadyOpen -and $p.Apps -notcontains 'chrome' -and $p.KeepApps -contains 'Discord' -and $p.KeepApps -contains 'Spotify') 'Keep app/default media protection lost'
Check (-not $p.EndsProcesses -and -not $p.ChangesGameAffinity -and -not $p.TouchesAntiCheat -and -not $p.PurgesMemory) 'Unexpected destructive policy'
$r=Invoke-BnqqCompetitiveStart -Action run -Game VALORANT-Win64-Shipping.exe -MaxMinutes 15
Check ($script:launched -eq 0 -and $script:controlled -eq 1 -and $r.Policy -eq 'Priority' -and $r.Apps -notcontains 'Discord' -and $r.Apps -notcontains 'Spotify' -and $r.Apps -notcontains 'vgc') 'Attach applied unsafe targets or relaunched game'
$script:running=$false;MustThrow {Invoke-BnqqCompetitiveStart -Action run -Game VALORANT-Win64-Shipping.exe}
$r=Invoke-BnqqCompetitiveStart -Action run -Game VALORANT-Win64-Shipping.exe -LaunchGame -Policy CpuSets -BackgroundCores 3
Check ($script:launched -eq 1 -and $r.Cores -eq 3 -and $r.Policy -eq 'CpuSets') 'Launch/soft-set delegation broken'
$script:others=@([pscustomobject]@{ProcessName='PRACC Performance';Id=400})
MustThrow {Invoke-BnqqCompetitiveStart -Action run -Game VALORANT-Win64-Shipping.exe}
Check ((Invoke-BnqqCompetitiveStart -Game VALORANT-Win64-Shipping.exe).BlockedReasons -contains 'OtherOptimizerRunning') 'Competing controller not reported'
$script:others=@();$script:ready=$false;MustThrow {Invoke-BnqqCompetitiveStart -Action run -Game VALORANT-Win64-Shipping.exe}
$script:ready=$true;$script:focus=[pscustomobject]@{Id='another'};MustThrow {Invoke-BnqqCompetitiveStart -Action run -Game VALORANT-Win64-Shipping.exe}
$script:focus=$null;$script:guardFails=$true;MustThrow {Invoke-BnqqCompetitiveStart -Action run -Game VALORANT-Win64-Shipping.exe}
Check ((Invoke-BnqqCompetitiveStart -Action stop).Status -eq 'StopRequested') 'Cooperative stop lost'
$script:BnqqCompetitiveRequestedUtc=[datetime]::UtcNow.AddMinutes(-1);MustThrow {Assert-BnqqCompetitiveNotCancelled}
$script:BnqqCompetitiveRequestedUtc=[datetime]::UtcNow.AddSeconds(1);Assert-BnqqCompetitiveNotCancelled
MustThrow {Invoke-BnqqCompetitiveStart -KeepApps 'chrome; shutdown'}
Check ((Invoke-BnqqCompetitiveStart -KeepApps msedge,chrome,firefox,OneDrive).BlockedReasons -contains 'NoBackgroundTargetsSelected') 'Empty participant selection not explained'
function Get-BnqqCompetitiveProcesses {[pscustomobject]@{ProcessName='cs2';Id=1};[pscustomobject]@{ProcessName='cs2';Id=2}}
MustThrow {Invoke-BnqqCompetitiveStart -Game cs2.exe}
# A real unsigned local fixture must never be accepted as the launcher.
$launchTemp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-launch-test-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($launchTemp)
function Get-ItemProperty {param($Path,$ErrorAction);[pscustomobject]@{SteamPath=$launchTemp}}
try{[IO.File]::WriteAllText((Join-Path $launchTemp 'steam.exe'),'not an executable');MustThrow {Get-BnqqCompetitiveLaunch cs2.exe}}
finally{$full=[IO.Path]::GetFullPath($launchTemp);if(-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture cleanup'};[IO.Directory]::Delete($full,$true);$full=[IO.Path]::GetFullPath($script:BnqqDataRoot);if(-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $full -Leaf) -notlike 'bnqq-start-test-*'){throw 'Unsafe fixture cleanup'};[IO.Directory]::Delete($full,$true)}
"PASS: competitive start $script:checks checks; attach/launch delegation, preserved voice, keep list, QA and competing-controller gates, soft-set opt-in, cooperative stop"
