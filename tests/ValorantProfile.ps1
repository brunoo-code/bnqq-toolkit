#Requires -Version 5.1
# Local temporary INIs only; no game, anti-cheat, registry or real user preferences.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
foreach($n in @('Core','GameProfile','ValorantProfile')){. (Join-Path $repo ('lib\'+$n+'.ps1'))}
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath());$temp=[IO.Path]::GetFullPath((Join-Path $base ('bnqq-valorant-'+[guid]::NewGuid().ToString('N'))))
if(-not $temp.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test path'}
$script:BnqqDataRoot=Join-Path $temp 'data';$script:checks=0;$script:gameOpen=$false
function Check($ok,$msg){if(-not $ok){throw $msg};$script:checks++}
function MustThrow([scriptblock]$Code){$hit=$false;try{& $Code|Out-Null}catch{$hit=$true};Check $hit 'Expected refusal'}
function Get-Process {param($Name,$ErrorAction);if($script:gameOpen){[pscustomobject]@{Name='VALORANT'}}}
function Get-BnqqValorantConfigRoot {Join-Path $temp 'Config'}
function Write-BnqqNightLog {param($Kind,$Message)}
[void][IO.Directory]::CreateDirectory($temp)
try{
 $text="[/Script/ShooterGame.ShooterGameUserSettings]`r`nResolutionSizeX=1280`r`nSensitivity=0.81`r`nsg.ShadowQuality=2`r`n[ScalabilityGroups]`r`n"
 foreach($k in (Get-BnqqValorantQualityKeys)){$text+=$k+" = 3 ; keep comment`r`n"}
 $text+="sg.ViewDistanceQuality=3`r`n[Unrelated]`r`nsg.TextureQuality=2`r`n; user bytes"
 $original=[Text.Encoding]::UTF8.GetBytes($text);$paths=@()
 foreach($n in 1..2){$f=Join-Path (Get-BnqqValorantConfigRoot) (('00000000-0000-0000-0000-00000000000'+$n+'-br\WindowsClient\GameUserSettings.ini'));[void][IO.Directory]::CreateDirectory((Split-Path $f -Parent));[IO.File]::WriteAllBytes($f,$original);$paths+=@($f)}
 $global=Join-Path (Get-BnqqValorantConfigRoot) 'WindowsClient\GameUserSettings.ini';[void][IO.Directory]::CreateDirectory((Split-Path $global -Parent));[IO.File]::WriteAllText($global,'[global]')
 Check (@(Find-BnqqValorantProfiles).Count -eq 2) 'Global/non-account config selected'
 $preview=Invoke-BnqqValorantProfile;Check ($preview.Status -ceq 'Preview' -and $preview.Profiles.Count -eq 2 -and -not (Test-Path $script:BnqqDataRoot)) 'Preview wrote files'
 MustThrow {Invoke-BnqqValorantProfile -Action apply}
 $out=[Text.Encoding]::UTF8.GetString((Convert-BnqqValorantLow $original))
 Check ($out.Contains('sg.ShadowQuality = 0 ; keep comment') -and $out.Contains('Sensitivity=0.81') -and $out.Contains('sg.ViewDistanceQuality=3') -and $out.Contains("sg.ShadowQuality=2`r`n[ScalabilityGroups]")) 'Patch changed unrelated bytes/sections'
 $bom=[Text.Encoding]::UTF8.GetPreamble()+$original
 Check ((Convert-BnqqValorantLow $bom)[0] -eq 239) 'BOM lost'
 MustThrow {Convert-BnqqValorantLow ([Text.Encoding]::Unicode.GetPreamble()+[Text.Encoding]::Unicode.GetBytes($text))}
 MustThrow {Convert-BnqqValorantLow ([Text.Encoding]::UTF8.GetBytes($text+"`r`n[ScalabilityGroups]`r`nsg.ShadowQuality=3"))}
 MustThrow {Convert-BnqqValorantLow ([Text.Encoding]::UTF8.GetBytes($text.Replace('sg.ShadowQuality = 3','sg.ShadowQuality = 4')))}
 MustThrow {Convert-BnqqValorantLow ([Text.Encoding]::UTF8.GetBytes($text.Replace('sg.ShadowQuality = 3',"sg.ShadowQuality=2`r`nsg.ShadowQuality = 3")))}
 MustThrow {Resolve-BnqqValorantProfilePath (Join-Path $temp 'outside\GameUserSettings.ini')}
 [IO.File]::SetAttributes($paths[0],[IO.FileAttributes]::ReadOnly)
 MustThrow {Invoke-BnqqValorantProfile -Action apply -AllProfiles}
 Check (([IO.File]::GetAttributes($paths[0]) -band [IO.FileAttributes]::ReadOnly) -ne 0) 'Read-only forcibly cleared'
 [IO.File]::SetAttributes($paths[0],[IO.FileAttributes]::Normal)
 $a=Invoke-BnqqValorantProfile -Action apply -AllProfiles
 Check ($a.Status -ceq 'Applied' -and $a.Changed -eq 2 -and -not $a.ReadOnlyEnforced -and -not $a.AntiCheatModified) 'Wrong apply state'
 $hash=(Get-FileHash -LiteralPath $a.Backup).Hash
 $again=Invoke-BnqqValorantProfile -Action apply -AllProfiles
 Check ($again.Status -ceq 'AlreadyConfigured' -and (Get-FileHash -LiteralPath $a.Backup).Hash -ceq $hash) 'Reapply overwrote backup'
 $script:gameOpen=$true;MustThrow {Invoke-BnqqValorantProfile -Action restore -BackupFile $a.Backup};$script:gameOpen=$false
 Invoke-BnqqValorantProfile -Action restore -BackupFile $a.Backup|Out-Null
 foreach($p in $paths){Check ((Get-BnqqByteHash ([IO.File]::ReadAllBytes($p))) -ceq (Get-BnqqByteHash $original)) 'Original bytes not restored'}
 Invoke-BnqqValorantProfile -Action restore -BackupFile $a.Backup|Out-Null
 $a=Invoke-BnqqValorantProfile -Action apply -AllProfiles
 [IO.File]::AppendAllText($paths[0],"`r`n; external edit")
 MustThrow {Invoke-BnqqValorantProfile -Action restore -BackupFile $a.Backup}
 Check ([IO.File]::ReadAllText($paths[0]).EndsWith('; external edit') -and (Get-BnqqValorantFile $paths[1]).Hash -ceq (Get-BnqqByteHash $original)) 'Conflict overwritten or independent profile not restored'
 MustThrow {Invoke-BnqqValorantProfile -Action apply -ProfilePath $paths[1]}
 [IO.File]::WriteAllBytes($paths[0],(Convert-BnqqValorantLow $original));Invoke-BnqqValorantProfile -Action restore -BackupFile $a.Backup|Out-Null
 # Failure after the second write must recover both originals from the prewritten journal.
 $script:realWriter=${function:Set-BnqqAtomicBytes};$script:failOnce=$true
 function Set-BnqqAtomicBytes {
  param($Path,[byte[]]$Bytes)
  $j=Get-ChildItem (Join-Path $script:BnqqDataRoot 'valorantprofiles') -Filter '*.json'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
  $state=Get-Content $j.FullName -Raw|ConvertFrom-Json;Check (@($state.Entries).Count -eq 2) 'All originals not durable before target writes'
  & $script:realWriter $Path $Bytes
  if($script:failOnce -and $Path -eq $paths[1]){$script:failOnce=$false;throw 'Injected write interruption'}
 }
 MustThrow {Invoke-BnqqValorantProfile -Action apply -AllProfiles}
 foreach($p in $paths){Check ((Get-BnqqValorantFile $p).Hash -ceq (Get-BnqqByteHash $original)) 'Interrupted batch did not recover original'}
 $j=Get-Content $a.Backup -Raw|ConvertFrom-Json;$j.Owner='wrong';Write-BnqqAtomicJson $j $a.Backup
 MustThrow {Invoke-BnqqValorantProfile -Action restore -BackupFile $a.Backup}
 # Client opening mid-batch leaves a recoverable journal instead of writing live prefs.
 $script:openOnce=$true
 function Set-BnqqAtomicBytes {
  param($Path,[byte[]]$Bytes)
  & $script:realWriter $Path $Bytes
  if($script:openOnce){$script:openOnce=$false;$script:gameOpen=$true}
 }
 MustThrow {Invoke-BnqqValorantProfile -Action apply -AllProfiles}
 $pending=Get-ChildItem (Join-Path $script:BnqqDataRoot 'valorantprofiles') -Filter '*.json'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
 $state=Get-Content $pending.FullName -Raw|ConvertFrom-Json
 Check ($state.Status -ceq 'NeedsRecovery' -and (Get-BnqqValorantFile $paths[1]).Hash -ceq (Get-BnqqByteHash $original)) 'Open-client interruption wrote remaining profile'
 $script:gameOpen=$false;Invoke-BnqqValorantProfile -Action restore -BackupFile $pending.FullName|Out-Null
 foreach($p in $paths){Check ((Get-BnqqValorantFile $p).Hash -ceq (Get-BnqqByteHash $original)) 'Deferred restore failed'}
 "PASS: Valorant profile $script:checks checks; scope, INI preservation, ownership, read-only respect, conflicts, rollback and durable batch"
}finally{
 if([IO.Path]::GetFullPath($temp) -ne $temp -or -not $temp.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
 if([IO.Directory]::Exists($temp)){Get-ChildItem -LiteralPath $temp -Recurse -File|ForEach-Object {[IO.File]::SetAttributes($_.FullName,[IO.FileAttributes]::Normal)};[IO.Directory]::Delete($temp,$true)}
}
