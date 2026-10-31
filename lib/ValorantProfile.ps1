# Offline preferences only. No service, process-priority, affinity or hardware identity changes.
function Get-BnqqValorantConfigRoot {Join-Path $env:LOCALAPPDATA 'VALORANT\Saved\Config'}
function Get-BnqqValorantQualityKeys {
 @('sg.ShadowQuality','sg.AntiAliasingQuality','sg.PostProcessQuality','sg.TextureQuality','sg.EffectsQuality','sg.FoliageQuality','sg.ShadingQuality')
}
function Resolve-BnqqValorantProfilePath {
 param([string]$Path)
 $root=[IO.Path]::GetFullPath((Get-BnqqValorantConfigRoot)).TrimEnd('\')+'\';$full=[IO.Path]::GetFullPath($Path)
 if(-not $full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Perfil fora da pasta local do VALORANT'}
 $relative=$full.Substring($root.Length)
 if($relative -notmatch '^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}(?:-[a-z0-9]+)?\\Windows(?:Client)?\\GameUserSettings\.ini$'){throw 'Caminho de perfil de conta nao reconhecido'}
 $probe=$full
 while($probe -and $probe.Length -ge $root.TrimEnd('\').Length){
  if(Test-Path -LiteralPath $probe){if((Get-Item -LiteralPath $probe -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Links de perfil nao admitidos'}}
  $probe=Split-Path $probe -Parent
 }
 $full
}
function Find-BnqqValorantProfiles {
 $root=Get-BnqqValorantConfigRoot
 if(-not (Test-Path -LiteralPath $root -PathType Container)){return @()}
 @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop|Where-Object {$_.Name -match '^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}(?:-[a-z0-9]+)?$'}|ForEach-Object {
  foreach($folder in @('WindowsClient','Windows')){$f=Join-Path $_.FullName ($folder+'\GameUserSettings.ini');if([IO.File]::Exists($f)){Resolve-BnqqValorantProfilePath $f}}
 }|Sort-Object -Unique)
}
function Convert-BnqqValorantLow {
 param([byte[]]$Bytes)
 if($Bytes.Length -gt 1048576 -or ($Bytes.Length -ge 2 -and (($Bytes[0] -eq 255 -and $Bytes[1] -eq 254) -or ($Bytes[0] -eq 254 -and $Bytes[1] -eq 255)))){throw 'Arquivo grande demais/UTF16 nao admitido'}
 $enc=[Text.Encoding]::GetEncoding(28591);$text=$enc.GetString($Bytes);$prefix=''
 if($Bytes.Length -ge 3 -and $Bytes[0] -eq 239 -and $Bytes[1] -eq 187 -and $Bytes[2] -eq 191){$prefix=$text.Substring(0,3);$text=$text.Substring(3)}
 $headers=@([regex]::Matches($text,'(?mi)^[ \t]*\[([^\]\r\n]+)\][ \t]*(?:[;#][^\r\n]*)?\r?$'))
 $sections=@($headers|Where-Object {$_.Groups[1].Value.Trim() -ieq 'ScalabilityGroups'})
 if($sections.Count -ne 1){throw 'ScalabilityGroups ausente/duplicado; nao adicionar chaves genericas'}
 $start=$sections[0].Index+$sections[0].Length;$end=$text.Length
 foreach($h in $headers){if($h.Index -gt $sections[0].Index){$end=$h.Index;break}}
 $body=$text.Substring($start,$end-$start)
 foreach($key in (Get-BnqqValorantQualityKeys)){
  $escaped=[regex]::Escape($key)
  if([regex]::Matches($body,('(?mi)^[ \t]*'+$escaped+'[ \t]*=')).Count -ne 1){throw ('Chave ausente/duplicada: '+$key)}
  $rx=New-Object Text.RegularExpressions.Regex ('(?mi)^([ \t]*'+$escaped+'[ \t]*=[ \t]*)([0-3])([ \t]*(?:[;#][^\r\n]*)?)(?=\r?$)')
  if($rx.Matches($body).Count -ne 1){throw ('Valor nao reconhecido: '+$key)}
  $body=$rx.Replace($body,'${1}0${3}')
 }
 return ,$enc.GetBytes($prefix+$text.Substring(0,$start)+$body+$text.Substring($end))
}
function Get-BnqqValorantFile {
 param([string]$Path)
 $full=Resolve-BnqqValorantProfilePath $Path;$item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
 if($item.PSIsContainer -or $item.Length -gt 1048576){throw 'Arquivo de perfil invalido/grande demais'}
 $bytes=[IO.File]::ReadAllBytes($full)
 [pscustomobject]@{File=$full;Bytes=$bytes;Hash=(Get-BnqqByteHash $bytes);ReadOnly=[bool]($item.Attributes -band [IO.FileAttributes]::ReadOnly)}
}
function Assert-BnqqValorantClosed {
 if(Get-Process -Name VALORANT,'VALORANT-Win64-Shipping',RiotClientServices -ErrorAction SilentlyContinue){throw 'Feche VALORANT e cliente Riot normalmente; nao serao encerrados automaticamente'}
}
function Restore-BnqqValorantProfile {
 param([string]$File)
 $item=Get-Item -LiteralPath $File -ErrorAction Stop;if($item.Length -gt 50331648){throw 'Journal grande demais'}
 $j=Get-Content -LiteralPath $File -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json
 if($j.Schema -cne 'BNQQ.ValorantProfile.1' -or $j.Owner -cne (Get-BnqqOwner) -or @($j.Entries).Count -lt 1 -or @($j.Entries).Count -gt 16){throw 'Schema/usuario de backup invalido'}
 $seen=@{}
 foreach($e in $j.Entries){
  $path=Resolve-BnqqValorantProfilePath $e.File
  if($path -cne $e.File -or $seen.ContainsKey($path)){throw 'Alvo de journal duplicado/invalido'};$seen[$path]=$true
  $before=[Convert]::FromBase64String($e.Before);$after=[Convert]::FromBase64String($e.After)
  if($before.Length -gt 1048576 -or $after.Length -gt 1048576 -or (Get-BnqqByteHash $before) -cne $e.BeforeHash -or (Get-BnqqByteHash $after) -cne $e.AfterHash -or (Get-BnqqByteHash (Convert-BnqqValorantLow $before)) -cne $e.AfterHash){throw 'Bytes/transicao de backup invalidos'}
 }
 $errors=@()
 foreach($e in $j.Entries){
  try{
   Assert-BnqqValorantClosed
   $current=Get-BnqqValorantFile $e.File
   if($current.Hash -ceq $e.BeforeHash){$e.Status='Restored'}
   elseif($current.Hash -ceq $e.AfterHash){
    if($current.ReadOnly){throw 'Perfil tornou-se somente leitura; nenhuma alteracao forcada'}
    Set-BnqqAtomicBytes $e.File ([Convert]::FromBase64String($e.Before))
    if((Get-BnqqValorantFile $e.File).Hash -cne $e.BeforeHash){throw 'Rollback nao verificado'};$e.Status='Restored'
   }else{throw ('Perfil mudou externamente: '+$e.File)}
  }catch{$errors+= $_.Exception.Message}
  Write-BnqqAtomicJson $j $File
 }
 $j.Status=if($errors.Count){'NeedsRecovery'}else{'Restored'};Write-BnqqAtomicJson $j $File
 if($errors.Count){throw ($errors -join '; ')}
 [pscustomobject]@{Status='Restored';Backup=$File;Profiles=@($j.Entries).Count;RebootRequired=$false}
}
function Invoke-BnqqValorantProfile {
 param([ValidateSet('plan','apply','restore')][string]$Action='plan',[string[]]$ProfilePath,[switch]$AllProfiles,[string]$BackupFile)
 if($Action -eq 'restore'){
  Assert-BnqqValorantClosed;$lock=Enter-BnqqStateLock
  try{return (Restore-BnqqValorantProfile $BackupFile)}finally{$lock.Dispose()}
 }
 if($ProfilePath -and $AllProfiles){throw 'Escolha ProfilePath ou AllProfiles'}
 $paths=if($ProfilePath){@($ProfilePath|ForEach-Object {Resolve-BnqqValorantProfilePath $_}|Sort-Object -Unique)}else{@(Find-BnqqValorantProfiles)}
 if(-not $paths.Count -or $paths.Count -gt 16){throw 'Nenhum perfil encontrado/limite de 16 perfis excedido'}
 if($Action -eq 'apply' -and $paths.Count -gt 1 -and -not $AllProfiles -and -not $ProfilePath){throw 'Multiplas contas; informe ProfilePath ou AllProfiles explicitamente'}
 $entries=@();foreach($p in $paths){
  $original=Get-BnqqValorantFile $p;$after=Convert-BnqqValorantLow $original.Bytes
  if($Action -eq 'apply' -and $original.ReadOnly){throw 'Arquivo somente leitura; nao remover protecao automaticamente'}
  $entries+=@([pscustomobject]@{File=$original.File;Before=[Convert]::ToBase64String($original.Bytes);BeforeHash=$original.Hash;After=[Convert]::ToBase64String($after);AfterHash=(Get-BnqqByteHash $after);Status='Prepared'})
 }
 if($Action -eq 'plan'){return [pscustomobject]@{Status='Preview';Profiles=@($entries|Select-Object File,BeforeHash,AfterHash);Keys=(Get-BnqqValorantQualityKeys);Level=0;RuntimeEffect='Not verified; client may override or ignore individual groups';FpsGainProven=$false;ReadOnlyEnforced=$false;AntiCheatModified=$false}}
 Assert-BnqqValorantClosed;$lock=Enter-BnqqStateLock;$file=$null
 try{
  foreach($pending in @(Get-ChildItem -LiteralPath (Join-Path (Get-BnqqDataRoot) 'valorantprofiles') -Filter '*.json' -File -ErrorAction SilentlyContinue)){
   $old=Get-Content -LiteralPath $pending.FullName -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json
   if($old.Status -notin @('Applied','Restored')){throw ('Recupere transacao pendente: '+$pending.FullName)}
  }
  $changed=@($entries|Where-Object {$_.BeforeHash -cne $_.AfterHash})
  if(-not $changed.Count){return [pscustomobject]@{Status='AlreadyConfigured';Profiles=$entries.Count;Changed=0;FpsGainProven=$false}}
  $file=Join-Path (Get-BnqqDataRoot) ('valorantprofiles\'+[guid]::NewGuid().ToString('N')+'.json')
  $j=[pscustomobject]@{Schema='BNQQ.ValorantProfile.1';Owner=(Get-BnqqOwner);Generated=[datetime]::UtcNow.ToString('o');Status='Prepared';Entries=$entries}
  Write-BnqqAtomicJson $j $file
  foreach($e in $entries){
   Assert-BnqqValorantClosed;$current=Get-BnqqValorantFile $e.File
   if($current.ReadOnly -or $current.Hash -cne $e.BeforeHash){throw 'Arquivo mudou durante a preparacao; interrompido'}
   if($current.Hash -cne $e.AfterHash){Set-BnqqAtomicBytes $e.File ([Convert]::FromBase64String($e.After))}
   if((Get-BnqqValorantFile $e.File).Hash -cne $e.AfterHash){throw 'Verificacao posterior falhou'}
   $e.Status='Applied';Write-BnqqAtomicJson $j $file
  }
  $j.Status='Applied';Write-BnqqAtomicJson $j $file
  [pscustomobject]@{Status='Applied';Profiles=$entries.Count;Changed=$changed.Count;Backup=$file;RebootRequired=$false;FpsGainProven=$false;ReadOnlyEnforced=$false;AntiCheatModified=$false}
 }catch{
  $failure=$_
  if($file -and [IO.File]::Exists($file)){
   try{Restore-BnqqValorantProfile $file|Out-Null}catch{$j.Status='NeedsRecovery';Write-BnqqAtomicJson $j $file;Write-BnqqNightLog 'VALORANT-PROFILE-RECOVERY' $_.Exception.Message}
  }
  throw $failure
 }finally{$lock.Dispose()}
}
function Show-BnqqValorantProfileMenu {
 $plan=Invoke-BnqqValorantProfile;$plan|Format-List
 Write-Host 'Preferencias locais existentes; efeito dentro do jogo ainda nao verificado. Vanguard e identidade do hardware intactos.'
 if((Read-Host ('Aplicar nos '+$plan.Profiles.Count+' perfis? Feche jogo/cliente Riot e digite SIM')) -ceq 'SIM'){Invoke-BnqqValorantProfile -Action apply -AllProfiles|Format-List}
}
