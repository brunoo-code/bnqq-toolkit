# Standard game preferences/configs only. Never changes archives, DLLs or anti-cheats.
function Get-BnqqCs2EngineValues {
 param([ValidateSet('CompetitiveLow','Minimum')][string]$Mode='CompetitiveLow')
 [ordered]@{'setting.msaa_samples'='0';'setting.r_csgo_cmaa_enable'='0';'setting.videocfg_shadow_quality'='0';'setting.videocfg_dynamic_shadows'=$(if($Mode -eq 'Minimum'){'0'}else{'1'});'setting.videocfg_texture_detail'='0';'setting.shaderquality'='0';'setting.r_texturefilteringquality'='0';'setting.videocfg_particle_detail'='0';'setting.videocfg_ao_detail'='0';'setting.videocfg_hdr_detail'='3';'setting.videocfg_fsr_detail'=$(if($Mode -eq 'Minimum'){'4'}else{'0'});'setting.mat_vsync'='0'}
}
function Convert-BnqqCs2EngineVideo {
 param([byte[]]$Bytes,[ValidateSet('CompetitiveLow','Minimum')][string]$Mode='CompetitiveLow')
 $enc=[Text.Encoding]::GetEncoding(28591);$text=$enc.GetString($Bytes)
 if([regex]::Matches($text,'"Version"\s+"16"').Count -ne 1){throw 'Somente schema de video 16 validado'}
 foreach($pair in (Get-BnqqCs2EngineValues $Mode).GetEnumerator()){
  $rx=New-Object Text.RegularExpressions.Regex ('("'+[regex]::Escape($pair.Key)+'"\s+")(-?\d+)(")')
  if($rx.Matches($text).Count -ne 1){throw ('Chave de video ausente/duplicada: '+$pair.Key)}
  $text=$rx.Replace($text,('${1}'+$pair.Value+'${3}'))
 }
 return ,$enc.GetBytes($text)
}
function Get-BnqqCs2EngineCfg {
 param([ValidateSet(0,1,2)][int]$BufferTicks=0)
 # These archived client settings are observed in the installed machine config.
 return ,([Text.Encoding]::ASCII.GetBytes((@('// BNQQ-CS2-ENGINE-1','// Standard client settings; not a subtick/input-latency or FPS guarantee.','fps_max 0','fps_max_ui 120','cl_joystick_enabled false',('cl_net_buffer_ticks '+$BufferTicks),'echo "BNQQ CS2 profile loaded"','') -join "`r`n")))
}
function Convert-BnqqCs2Autoexec {
 param([byte[]]$Bytes)
 if($Bytes.Length -ge 2 -and (($Bytes[0] -eq 255 -and $Bytes[1] -eq 254) -or ($Bytes[0] -eq 254 -and $Bytes[1] -eq 255))){throw 'Autoexec UTF-16 nao alterado automaticamente'}
 $enc=[Text.Encoding]::GetEncoding(28591);$text=$enc.GetString($Bytes)
 $block="// BNQQ ENGINE BEGIN`r`nexec bnqq_competitive.cfg`r`n// BNQQ ENGINE END`r`n"
 $starts=[regex]::Matches($text,'(?m)^// BNQQ ENGINE BEGIN\r?$').Count
 $ends=[regex]::Matches($text,'(?m)^// BNQQ ENGINE END\r?$').Count
 if($starts -or $ends){
  if($starts -ne 1 -or $ends -ne 1 -or [regex]::Matches($text,'(?m)^// BNQQ ENGINE BEGIN\r?\nexec bnqq_competitive\.cfg\r?\n// BNQQ ENGINE END\r?$').Count -ne 1){throw 'Bloco BNQQ alterado/ambiguo no autoexec'}
  return ,$Bytes
 }
 if($text.Length -and -not $text.EndsWith("`n")){$text+="`r`n"}
 return ,$enc.GetBytes($text+$block)
}
function Get-BnqqCs2EngineShortcutPath {Join-Path ([Environment]::GetFolderPath('Desktop')) 'BNQQ\CS2 - BNQQ.lnk'}
function Resolve-BnqqCs2EnginePaths {
 param([string]$Directory,[string]$GameCfgDirectory,[string]$SteamExe)
 if(-not $Directory){$dirs=@(Find-BnqqCs2Configs);if($dirs.Count -ne 1){throw 'Selecione um perfil Steam com -GameConfigDirectory'};$Directory=$dirs[0]}
 if(-not $SteamExe){$steam=(Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath;$SteamExe=Join-Path $steam 'steam.exe'}
 if(-not $GameCfgDirectory){
  $steam=Split-Path $SteamExe -Parent;$roots=@($steam);$libraries=Join-Path $steam 'steamapps\libraryfolders.vdf'
  if(Test-Path -LiteralPath $libraries){$text=[IO.File]::ReadAllText($libraries);if($text.Length -gt 1048576){throw 'Inventario Steam grande demais'};foreach($m in [regex]::Matches($text,'"path"\s+"([^"\r\n]+)"')){$roots+=@($m.Groups[1].Value.Replace('\\','\'))}}
  $found=@($roots|Select-Object -Unique|ForEach-Object {$p=Join-Path $_ 'steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg';if([IO.File]::Exists((Join-Path $p '..\..\bin\win64\cs2.exe'))){[IO.Path]::GetFullPath($p)}}|Sort-Object -Unique)
  if($found.Count -ne 1){throw 'Instalacao CS2 ausente/ambigua; informe -GameCfgDirectory'};$GameCfgDirectory=$found[0]
 }
 $directory=[IO.Path]::GetFullPath($Directory);$gameCfgDirectory=[IO.Path]::GetFullPath($GameCfgDirectory);$steamExe=[IO.Path]::GetFullPath($SteamExe)
 foreach($p in @($directory,$gameCfgDirectory,$steamExe)){if($p.StartsWith('\\')){throw 'Caminhos de rede nao admitidos'}}
 if(-not [IO.File]::Exists((Join-Path $directory 'cs2_video.txt')) -or -not [IO.Directory]::Exists($gameCfgDirectory) -or -not [IO.File]::Exists((Join-Path $gameCfgDirectory '..\..\bin\win64\cs2.exe')) -or [IO.Path]::GetFileName($steamExe) -ine 'steam.exe' -or -not [IO.File]::Exists($steamExe)){throw 'Perfil/instalacao/Steam invalido'}
 [pscustomobject]@{Directory=$directory;GameCfgDirectory=$gameCfgDirectory;SteamExe=$steamExe;Shortcut=[IO.Path]::GetFullPath((Get-BnqqCs2EngineShortcutPath))}
}
function Get-BnqqCs2EngineAssetPaths {
 param($Paths)
 [ordered]@{Video=(Join-Path $Paths.Directory 'cs2_video.txt');Config=(Join-Path $Paths.GameCfgDirectory 'bnqq_competitive.cfg');Autoexec=(Join-Path $Paths.GameCfgDirectory 'autoexec.cfg');Shortcut=$Paths.Shortcut}
}
function Get-BnqqCs2EngineFile {
 param([string]$Path)
 if(-not [IO.File]::Exists($Path)){return [pscustomobject]@{Exists=$false;Bytes=[byte[]]@();Hash=$null}}
 $f=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($f.Length -gt 1048576 -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Arquivo grande demais ou link nao admitido'}
 $b=[IO.File]::ReadAllBytes($Path);[pscustomobject]@{Exists=$true;Bytes=$b;Hash=(Get-BnqqByteHash $b)}
}
function Set-BnqqCs2EngineBytes {
 param([string]$Path,[byte[]]$Bytes)
 if([IO.File]::Exists($Path)){Set-BnqqAtomicBytes $Path $Bytes;return}
 $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{
  $s=New-Object IO.FileStream($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$s.Write($Bytes,0,$Bytes.Length);$s.Flush($true)}finally{$s.Dispose()}
  [IO.File]::Move($temp,$Path)
 }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
}
function New-BnqqCs2EngineLinkBytes {
 param($Paths)
 $temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-cs2-'+[guid]::NewGuid().ToString('N')+'.lnk')
 try{
  $shell=New-Object -ComObject WScript.Shell;$link=$shell.CreateShortcut($temp);$link.TargetPath=$Paths.SteamExe;$link.Arguments='-applaunch 730 +exec bnqq_competitive.cfg';$link.WorkingDirectory=Split-Path $Paths.SteamExe -Parent;$link.Description='BNQQ CS2: configuracoes nativas; sem injecao';$link.Save()
  return ,([IO.File]::ReadAllBytes($temp))
 }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
}
function Get-BnqqCs2EnginePlan {
 param($Paths,[ValidateSet('CompetitiveLow','Minimum')][string]$Mode='CompetitiveLow',[ValidateSet(0,1,2)][int]$BufferTicks=0)
 $machine=Join-Path $Paths.Directory 'cs2_machine_convars.vcfg';$text=[IO.File]::ReadAllText($machine)
 foreach($key in @('fps_max','fps_max_ui(?:\$2)?','cl_joystick_enabled','cl_net_buffer_ticks')){if([regex]::Matches($text,('"'+$key+'"\s+"[^"\r\n]+"')).Count -ne 1){throw 'Cvar de cliente ausente/ambigua na configuracao instalada'}}
 $files=Get-BnqqCs2EngineAssetPaths $Paths;$entries=@()
 foreach($kind in @('Video','Config','Autoexec','Shortcut')){
  $path=$files[$kind];$before=Get-BnqqCs2EngineFile $path
  if($before.Exists -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReadOnly)){throw ('Arquivo somente leitura; nao forcar: '+$path)}
  $after=$null
  switch($kind){
   'Video' {$after=Convert-BnqqCs2EngineVideo $before.Bytes $Mode}
   'Config' {
    if($before.Exists){$known=$false;foreach($n in 0..2){if($before.Hash -ceq (Get-BnqqByteHash (Get-BnqqCs2EngineCfg $n))){$known=$true}};if(-not $known){throw 'bnqq_competitive.cfg existente nao e uma versao gerenciada reconhecida'}}
    $after=Get-BnqqCs2EngineCfg $BufferTicks
   }
   'Autoexec' {$after=Convert-BnqqCs2Autoexec $before.Bytes}
   'Shortcut' {
    if($before.Exists){$shell=New-Object -ComObject WScript.Shell;$link=$shell.CreateShortcut($path);if($link.TargetPath -ine $Paths.SteamExe -or $link.Arguments -cne '-applaunch 730 +exec bnqq_competitive.cfg'){throw 'Atalho existente divergente; nao sobrescrever'};$after=$before.Bytes}
   }
  }
  if($null -ne $after -and $after.Length -gt 1048576){throw ('Resultado grande demais: '+$kind)}
  $entries+=@([pscustomobject]@{Kind=$kind;Path=$path;BeforeExisted=$before.Exists;Before=[Convert]::ToBase64String($before.Bytes);BeforeHash=$before.Hash;AfterBytes=$after;AfterHash=$(if($null -ne $after){Get-BnqqByteHash $after});Status='Prepared'})
 }
 [pscustomobject]@{Status='Preview';Mode=$Mode;BufferTicks=$BufferTicks;Paths=$Paths;Entries=$entries;VideoValues=(Get-BnqqCs2EngineValues $Mode);LaunchOptions='-applaunch 730 +exec bnqq_competitive.cfg';ExcludedNotApplied=@('-high','-threads','-novid','-nojoy','m_rawinput','m_customaccel','cl_interp','cl_interp_ratio','cl_updaterate','cl_cmdrate','sky/water/blood removal','subtick smoothing');Notes='Normal menu values only. Minimum lowers visibility/shadow cues and uses blurry FSR Performance. Rate, sensitivity, resolution, refresh and existing Reflex are preserved. Buffering trades latency for jitter tolerance.';FpsGainProven=$false;BanRiskGuarantee=$false}
}
function Restore-BnqqCs2Engine {
 param([string]$File)
 $item=Get-Item -LiteralPath $File -ErrorAction Stop;if($item.Length -gt 16777216){throw 'Backup grande demais'}
 $j=Get-Content -LiteralPath $File -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json
 if($j.Schema -cne 'BNQQ.Cs2Engine.1' -or $j.Owner -cne (Get-BnqqOwner) -or $j.Mode -notin @('Minimum','CompetitiveLow') -or $j.BufferTicks -notin @(0,1,2) -or @($j.Entries).Count -ne 4){throw 'Backup/schema de engine invalido'}
 $paths=Resolve-BnqqCs2EnginePaths $j.Paths.Directory $j.Paths.GameCfgDirectory $j.Paths.SteamExe;$expectedPaths=Get-BnqqCs2EngineAssetPaths $paths;$seen=@{}
 foreach($e in $j.Entries){
  if($e.Kind -notin @('Video','Config','Autoexec','Shortcut') -or $seen.ContainsKey($e.Kind) -or $e.Path -cne $expectedPaths[$e.Kind] -or $e.BeforeExisted -isnot [bool]){throw 'Alvo de backup invalido'};$seen[$e.Kind]=$true
  $before=[Convert]::FromBase64String($e.Before);$after=[Convert]::FromBase64String($e.After)
  if($before.Length -gt 1048576 -or $after.Length -gt 1048576 -or ($e.BeforeExisted -and (Get-BnqqByteHash $before) -cne $e.BeforeHash) -or (-not $e.BeforeExisted -and ($before.Length -or $e.BeforeHash))){throw 'Original corrompido'}
  $derived=switch($e.Kind){'Video'{if(-not $e.BeforeExisted){throw 'Video original ausente'};Convert-BnqqCs2EngineVideo $before $j.Mode}'Config'{if($e.BeforeExisted){$known=$false;foreach($n in 0..2){if($e.BeforeHash -ceq (Get-BnqqByteHash (Get-BnqqCs2EngineCfg $n))){$known=$true}};if(-not $known){throw 'Original do cfg gerenciado nao reconhecido'}};Get-BnqqCs2EngineCfg $j.BufferTicks}'Autoexec'{Convert-BnqqCs2Autoexec $before}'Shortcut'{$after}}
  if((Get-BnqqByteHash $derived) -cne $e.AfterHash -or (Get-BnqqByteHash $after) -cne $e.AfterHash){throw 'Transicao de backup nao reconhecida'}
 }
 $errors=@()
 foreach($e in @($j.Entries|Select-Object -Last 4|Sort-Object @{Expression={[array]::IndexOf(@('Shortcut','Autoexec','Config','Video'),$_.Kind)}})){
  if($e.Status -ceq 'Restored'){continue}
  try{
   if(Get-Process -Name cs2 -ErrorAction SilentlyContinue){throw 'CS2 abriu durante restauracao; restante adiado'}
   $current=Get-BnqqCs2EngineFile $e.Path
   if($current.Exists -eq $e.BeforeExisted -and $current.Hash -ceq $e.BeforeHash){$e.Status='Restored'}
   elseif($current.Exists -and $current.Hash -ceq $e.AfterHash){
    if($e.BeforeExisted){Set-BnqqCs2EngineBytes $e.Path ([Convert]::FromBase64String($e.Before))}else{[IO.File]::Delete($e.Path)}
    $actual=Get-BnqqCs2EngineFile $e.Path;if($actual.Exists -ne $e.BeforeExisted -or $actual.Hash -cne $e.BeforeHash){throw 'Rollback nao verificado'};$e.Status='Restored'
   }else{throw ('Arquivo mudou externamente: '+$e.Kind)}
  }catch{$errors+= $_.Exception.Message}
  Write-BnqqAtomicJson $j $File
 }
 $j.Status=if($errors.Count){'NeedsRecovery'}else{'Restored'};Write-BnqqAtomicJson $j $File
 if($errors.Count){throw ($errors -join '; ')}
 [pscustomobject]@{Status='Restored';Backup=$File;RebootRequired=$false}
}
function Invoke-BnqqCs2Engine {
 param([ValidateSet('plan','apply','restore')][string]$Action='plan',[string]$Directory,[string]$GameCfgDirectory,[string]$SteamExe,[ValidateSet('CompetitiveLow','Minimum')][string]$Mode='CompetitiveLow',[ValidateSet(0,1,2)][int]$BufferTicks=0,[string]$BackupFile)
 if($Action -eq 'restore'){
  if(Get-Process -Name cs2 -ErrorAction SilentlyContinue){throw 'Feche CS2 normalmente antes de restaurar'}
  $lock=Enter-BnqqStateLock;try{return (Restore-BnqqCs2Engine $BackupFile)}finally{$lock.Dispose()}
 }
 $paths=Resolve-BnqqCs2EnginePaths $Directory $GameCfgDirectory $SteamExe;$plan=Get-BnqqCs2EnginePlan $paths $Mode $BufferTicks
 if($Action -eq 'plan'){
  return [pscustomobject]@{Status='Preview';Mode=$Mode;BufferTicks=$BufferTicks;Paths=$paths;VideoValues=$plan.VideoValues;Assets=@($plan.Entries|Select-Object Kind,Path,BeforeExisted,BeforeHash,AfterHash);LaunchOptions=$plan.LaunchOptions;ExcludedNotApplied=$plan.ExcludedNotApplied;Notes=$plan.Notes;FpsGainProven=$false;BanRiskGuarantee=$false}
 }
 if(Get-Process -Name cs2 -ErrorAction SilentlyContinue){throw 'Feche CS2 normalmente antes de aplicar'}
 $lock=Enter-BnqqStateLock;$file=$null
 try{
  foreach($pending in @(Get-ChildItem -LiteralPath (Join-Path (Get-BnqqDataRoot) 'engineprofiles') -Filter '*.json' -File -ErrorAction SilentlyContinue)){
   $state=Get-Content -LiteralPath $pending.FullName -Raw -ErrorAction Stop|ConvertFrom-Json
   if($state.Status -notin @('Applied','Restored')){throw ('Recuperar transacao de engine pendente: '+$pending.FullName)}
  }
  $entries=@($plan.Entries)
  $link=$entries|Where-Object Kind -ceq 'Shortcut';if($null -eq $link.AfterBytes){$link.AfterBytes=New-BnqqCs2EngineLinkBytes $paths;$link.AfterHash=Get-BnqqByteHash $link.AfterBytes}
  $changed=@($entries|Where-Object {$_.BeforeHash -cne $_.AfterHash})
  if(-not $changed.Count){return [pscustomobject]@{Status='AlreadyConfigured';Mode=$Mode;Changed=0}}
  foreach($e in $entries){$e|Add-Member NoteProperty After ([Convert]::ToBase64String($e.AfterBytes));$e.PSObject.Properties.Remove('AfterBytes')}
  $file=Join-Path (Get-BnqqDataRoot) ('engineprofiles\'+[guid]::NewGuid().ToString('N')+'.json')
  $j=[pscustomobject]@{Schema='BNQQ.Cs2Engine.1';Owner=(Get-BnqqOwner);Generated=[datetime]::UtcNow.ToString('o');Status='Prepared';Mode=$Mode;BufferTicks=$BufferTicks;Paths=$paths;Entries=$entries}
  Write-BnqqAtomicJson $j $file
  foreach($e in $entries){
   if(Get-Process -Name cs2 -ErrorAction SilentlyContinue){throw 'CS2 abriu durante a aplicacao; interrompido'}
   $current=Get-BnqqCs2EngineFile $e.Path;if($current.Exists -ne $e.BeforeExisted -or $current.Hash -cne $e.BeforeHash){throw ('Arquivo mudou durante preparacao: '+$e.Kind)}
   if($current.Hash -cne $e.AfterHash){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($e.Path));Set-BnqqCs2EngineBytes $e.Path ([Convert]::FromBase64String($e.After))}
   if((Get-BnqqCs2EngineFile $e.Path).Hash -cne $e.AfterHash){throw 'Verificacao posterior falhou'}
   $e.Status='Applied';Write-BnqqAtomicJson $j $file
  }
  $j.Status='Applied';Write-BnqqAtomicJson $j $file
  [pscustomobject]@{Status='Applied';Mode=$Mode;Changed=$changed.Count;Backup=$file;Shortcut=$paths.Shortcut;RequiresGameRestart=$true;RebootRequired=$false;FpsGainProven=$false}
 }catch{
  $failure=$_
  if($file -and [IO.File]::Exists($file)){
   if(-not (Get-Process -Name cs2 -ErrorAction SilentlyContinue)){try{Restore-BnqqCs2Engine $file|Out-Null}catch{Write-BnqqNightLog 'CS2-ENGINE-RECOVERY' $_.Exception.Message}}
   else{$j.Status='NeedsRecovery';Write-BnqqAtomicJson $j $file;Write-BnqqNightLog 'CS2-ENGINE-PENDING' ('CS2 aberto; restauracao adiada: '+$file)}
  }
  throw $failure
 }finally{$lock.Dispose()}
}
function Show-BnqqCs2EngineMenu {
 Write-Host 'Somente preferencias nativas. Minimum reduz nitidez e sombras; nao ha promessa de FPS ou risco zero de ban.'
 $mode=Read-Host '1=Competitivo Baixo (sombras All/FSR off), 2=Minimo (SunOnly/FSR Performance); outro cancela'
 if($mode -notin @('1','2')){return};$preset=if($mode -eq '1'){'CompetitiveLow'}else{'Minimum'}
 Invoke-BnqqCs2Engine -Mode $preset|Format-List
 if((Read-Host 'CS2 fechado: aplicar com backup? Digite SIM') -ceq 'SIM'){Invoke-BnqqCs2Engine -Action apply -Mode $preset|Format-List}
}
