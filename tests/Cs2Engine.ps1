#Requires -Version 5.1
# Temporary config files and a real .lnk only. Never launches Steam/CS2 or changes Windows.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
foreach($n in @('Core','GameProfile','Cs2Engine','FramePacing')){. (Join-Path $repo ('lib\'+$n+'.ps1'))}
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath());$temp=[IO.Path]::GetFullPath((Join-Path $base ('bnqq-engine-'+[guid]::NewGuid().ToString('N'))))
if(-not $temp.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture path'}
$script:BnqqDataRoot=Join-Path $temp 'data';$script:checks=0;$script:gameOpen=$false
function Check($ok,$msg){if(-not $ok){throw $msg};$script:checks++}
function MustThrow([scriptblock]$code){$hit=$false;try{& $code|Out-Null}catch{$hit=$true};Check $hit 'Expected engine refusal'}
function Get-Process {param($Name,$ErrorAction);if($script:gameOpen){[pscustomobject]@{Name='cs2'}}}
function Write-BnqqNightLog {param($Kind,$Message)}
function Get-BnqqCs2EngineShortcutPath {Join-Path $temp 'Desktop\BNQQ\CS2 - BNQQ.lnk'}
[void][IO.Directory]::CreateDirectory($temp)
try{
 $user=Join-Path $temp 'userdata\123\730\local\cfg';$game=Join-Path $temp 'game\csgo\cfg';$bin=Join-Path $temp 'game\bin\win64'
 foreach($d in @($user,$game,$bin)){[void][IO.Directory]::CreateDirectory($d)}
 $steam=Join-Path $temp 'steam.exe';[IO.File]::WriteAllBytes($steam,[byte[]]@(1));[IO.File]::WriteAllBytes((Join-Path $bin 'cs2.exe'),[byte[]]@(1))
 $values=Get-BnqqCs2EngineValues CompetitiveLow;$values['setting.msaa_samples']='2';$values['setting.videocfg_shadow_quality']='2';$values['setting.videocfg_hdr_detail']='-1'
 $text="`"video.cfg`"`r`n{`r`n`"Version`" `"16`"`r`n`"setting.defaultres`" `"1280`"`r`n`"setting.r_low_latency`" `"2`"`r`n"
 foreach($p in $values.GetEnumerator()){$text+=('"'+$p.Key+'" "'+$p.Value+'"'+"`r`n")};$text+="}// ação"
 $video=Join-Path $user 'cs2_video.txt';$original=[Text.Encoding]::UTF8.GetBytes($text);[IO.File]::WriteAllBytes($video,$original)
 [IO.File]::WriteAllText((Join-Path $user 'cs2_machine_convars.vcfg'),'"fps_max" "400" "fps_max_ui$2" "120" "cl_joystick_enabled" "false" "cl_net_buffer_ticks" "0"')
 $autoexec=Join-Path $game 'autoexec.cfg';$originalAuto=[Text.Encoding]::UTF8.GetBytes("// ação`r`nsensitivity 0.81`r`nbind x +voicerecord")
 [IO.File]::WriteAllBytes($autoexec,$originalAuto)
 $paths=Resolve-BnqqCs2EnginePaths $user $game $steam
 $plan=Invoke-BnqqCs2Engine -Directory $user -GameCfgDirectory $game -SteamExe $steam -Mode Minimum
 Check ($plan.Status -ceq 'Preview' -and -not (Test-Path -LiteralPath $paths.Shortcut)) 'Plan created shortcut'
 Check ((Get-BnqqByteHash ([IO.File]::ReadAllBytes($video))) -ceq (Get-BnqqByteHash $original)) 'Plan changed video'
 $a=Invoke-BnqqCs2Engine -Action apply -Directory $user -GameCfgDirectory $game -SteamExe $steam -Mode Minimum
 $out=[IO.File]::ReadAllText($video)
 Check ($a.Status -ceq 'Applied' -and $out.Contains('"setting.msaa_samples" "0"') -and $out.Contains('"setting.videocfg_hdr_detail" "3"') -and $out.Contains('"setting.videocfg_fsr_detail" "4"')) 'Minimum settings not applied'
 Check ($out.Contains('"setting.defaultres" "1280"') -and $out.Contains('"setting.r_low_latency" "2"')) 'Resolution/Reflex modified'
 Check ([IO.File]::ReadAllText($autoexec).StartsWith([Text.Encoding]::UTF8.GetString($originalAuto))) 'Existing binds/sensitivity changed'
 $cfg=[IO.File]::ReadAllText((Join-Path $game 'bnqq_competitive.cfg'))
 Check ($cfg -notmatch 'cl_interp|m_rawinput|sv_cheats|r_draw|rate |bind |alias ') 'Generated cfg contains unadmitted commands'
 Check ($cfg -notmatch '(?m)^fps_max(?:_ui)?\s') 'Engine cfg overrides native frame caps'
 $caps=Invoke-BnqqFramePacing -Directory $user -Action apply -GameCap 240 -MenuCap 120
 Check ([IO.File]::ReadAllText((Join-Path $user 'cs2_machine_convars.vcfg')).Contains('"fps_max" "240"') -and [IO.File]::ReadAllText((Join-Path $game 'bnqq_competitive.cfg')) -ceq $cfg) 'Native cap not respected independently of engine cfg'
 Invoke-BnqqFramePacing -Directory $user -Action restore -BackupFile $caps.Backup|Out-Null
 $link=(New-Object -ComObject WScript.Shell).CreateShortcut($paths.Shortcut)
 Check ($link.TargetPath -ieq $steam -and $link.Arguments -ceq '-applaunch 730 +exec bnqq_competitive.cfg') 'Launch shortcut wrong'
 $hash=(Get-FileHash -LiteralPath $a.Backup -Algorithm SHA256).Hash
 $again=Invoke-BnqqCs2Engine -Action apply -Directory $user -GameCfgDirectory $game -SteamExe $steam -Mode Minimum
 Check ($again.Status -ceq 'AlreadyConfigured' -and (Get-FileHash -LiteralPath $a.Backup -Algorithm SHA256).Hash -ceq $hash) 'Reapply overwrote backup'
 Invoke-BnqqCs2Engine -Action restore -BackupFile $a.Backup|Out-Null
 Check ((Get-BnqqByteHash ([IO.File]::ReadAllBytes($video))) -ceq (Get-BnqqByteHash $original) -and (Get-BnqqByteHash ([IO.File]::ReadAllBytes($autoexec))) -ceq (Get-BnqqByteHash $originalAuto)) 'Byte-exact originals not restored'
 Check (-not [IO.File]::Exists($paths.Shortcut) -and -not [IO.File]::Exists((Join-Path $game 'bnqq_competitive.cfg'))) 'Created files not removed'
 Invoke-BnqqCs2Engine -Action restore -BackupFile $a.Backup|Out-Null
 # Historical journals had no ConfigVersion and generated the legacy unlimited cfg.
 $legacy=Invoke-BnqqCs2Engine -Action apply -Directory $user -GameCfgDirectory $game -SteamExe $steam -Mode Minimum
 $legacyData=Get-Content $legacy.Backup -Raw|ConvertFrom-Json;$legacyData.PSObject.Properties.Remove('ConfigVersion')
 $legacyEntry=$legacyData.Entries|Where-Object Kind -eq 'Config';$legacyBytes=Get-BnqqCs2EngineCfg -BufferTicks 0 -Version 1
 $legacyEntry.After=[Convert]::ToBase64String($legacyBytes);$legacyEntry.AfterHash=Get-BnqqByteHash $legacyBytes
 [IO.File]::WriteAllBytes($legacyEntry.Path,$legacyBytes);Write-BnqqAtomicJson $legacyData $legacy.Backup
 Invoke-BnqqCs2Engine -Action restore -BackupFile $legacy.Backup|Out-Null
 Check ((Get-BnqqByteHash ([IO.File]::ReadAllBytes($video))) -ceq (Get-BnqqByteHash $original) -and -not [IO.File]::Exists($legacyEntry.Path)) 'Legacy journal compatibility lost'
 $a=Invoke-BnqqCs2Engine -Action apply -Directory $user -GameCfgDirectory $game -SteamExe $steam -Mode CompetitiveLow
 Check ([IO.File]::ReadAllText($video).Contains('"setting.videocfg_fsr_detail" "0"') -and [IO.File]::ReadAllText($video).Contains('"setting.videocfg_dynamic_shadows" "1"')) 'CompetitiveLow dropped visibility choices'
 [IO.File]::AppendAllText($video,'// external')
 MustThrow {Invoke-BnqqCs2Engine -Action restore -BackupFile $a.Backup}
 Check ([IO.File]::ReadAllText($video).EndsWith('// external') -and -not [IO.File]::Exists($paths.Shortcut)) 'Conflict overwritten or independent asset not restored'
 [IO.File]::WriteAllBytes($video,(Convert-BnqqCs2EngineVideo $original CompetitiveLow));Invoke-BnqqCs2Engine -Action restore -BackupFile $a.Backup|Out-Null
 $script:gameOpen=$true;MustThrow {Invoke-BnqqCs2Engine -Action apply -Directory $user -GameCfgDirectory $game -SteamExe $steam};$script:gameOpen=$false
 MustThrow {Convert-BnqqCs2Autoexec ([Text.Encoding]::Unicode.GetPreamble()+[Text.Encoding]::Unicode.GetBytes('echo x'))}
 MustThrow {Convert-BnqqCs2Autoexec ([Text.Encoding]::ASCII.GetBytes("// BNQQ ENGINE BEGIN`r`nexec evil.cfg`r`n// BNQQ ENGINE END"))}
 [IO.File]::WriteAllText((Join-Path $game 'bnqq_competitive.cfg'),'// user-owned content')
 MustThrow {Invoke-BnqqCs2Engine -Action apply -Directory $user -GameCfgDirectory $game -SteamExe $steam}
 [IO.File]::Delete((Join-Path $game 'bnqq_competitive.cfg'))
 # An absent autoexec is created and then deleted on rollback.
 [IO.File]::Delete($autoexec)
 $a=Invoke-BnqqCs2Engine -Action apply -Directory $user -GameCfgDirectory $game -SteamExe $steam
 Invoke-BnqqCs2Engine -Action restore -BackupFile $a.Backup|Out-Null
 Check (-not [IO.File]::Exists($autoexec)) 'Previously absent autoexec not restored as absent'
 # Simulate an interruption after a target write; originals must already be durable.
 $script:realEngineWriter=${function:Set-BnqqCs2EngineBytes};$script:interruptOnce=$true
 function Set-BnqqCs2EngineBytes {
  param($Path,[byte[]]$Bytes)
  $journal=Get-ChildItem (Join-Path $script:BnqqDataRoot 'engineprofiles') -Filter '*.json'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
  $j=Get-Content $journal.FullName -Raw|ConvertFrom-Json
  Check (@($j.Entries).Count -eq 4) 'All original states were not durable before writing'
  & $script:realEngineWriter $Path $Bytes
  if($script:interruptOnce -and [IO.Path]::GetFileName($Path) -ceq 'autoexec.cfg'){$script:interruptOnce=$false;throw 'Interrupted after target write'}
 }
 MustThrow {Invoke-BnqqCs2Engine -Action apply -Directory $user -GameCfgDirectory $game -SteamExe $steam -Mode Minimum}
 Check ((Get-BnqqByteHash ([IO.File]::ReadAllBytes($video))) -ceq (Get-BnqqByteHash $original) -and -not [IO.File]::Exists($autoexec) -and -not [IO.File]::Exists($paths.Shortcut)) 'Interrupted application not recovered'
 # Tampered transition is rejected before modifying any target.
 $j=Get-Content $a.Backup -Raw|ConvertFrom-Json;$j.Mode='Minimum';Write-BnqqAtomicJson $j $a.Backup
 MustThrow {Invoke-BnqqCs2Engine -Action restore -BackupFile $a.Backup}
 "PASS: CS2 engine $script:checks checks; modes, preservation, launcher, byte rollback, ownership, conflicts and open-game refusal"
}finally{
 if([IO.Path]::GetFullPath($temp) -ne $temp -or -not $temp.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
 if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
}
