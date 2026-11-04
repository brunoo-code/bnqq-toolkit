# Supported browser preferences, per-user only. No repackaged clients or security changes.
function Get-BnqqAppLiteCatalog {
 @([pscustomobject]@{App='Edge';Path='HKCU:\Software\Policies\Microsoft\Edge';Name='StartupBoostEnabled';Value=0},
 [pscustomobject]@{App='Edge';Path='HKCU:\Software\Policies\Microsoft\Edge';Name='BackgroundModeEnabled';Value=0},
 [pscustomobject]@{App='Edge';Path='HKCU:\Software\Policies\Microsoft\Edge';Name='SleepingTabsEnabled';Value=1},
 [pscustomobject]@{App='Edge';Path='HKCU:\Software\Policies\Microsoft\Edge';Name='SleepingTabsTimeout';Value=300},
 [pscustomobject]@{App='Chrome';Path='HKCU:\Software\Policies\Google\Chrome';Name='BackgroundModeEnabled';Value=0})
}
function Test-BnqqBrowserInstalled {
 param([ValidateSet('Edge','Chrome')][string]$App)
 $sub=if($App -eq 'Edge'){'Microsoft\Edge\Application\msedge.exe'}else{'Google\Chrome\Application\chrome.exe'}
 foreach($root in @($env:ProgramFiles,${env:ProgramFiles(x86)},$env:LOCALAPPDATA)){if($root -and [IO.File]::Exists((Join-Path $root $sub))){return $true}}
 return $false
}
function Test-BnqqLiteSnapshot {
 param($A,$B)
 if($A.Path -cne $B.Path -or $A.Name -cne $B.Name -or $A.Existed -ne $B.Existed){return $false}
 if(-not $A.Existed){return $true}
 return ($A.Kind -ceq $B.Kind -and (Test-BnqqSameValue $A.Value $B.Value))
}
function Get-BnqqAppLitePlan {
 param([ValidateSet('Edge','Chrome')][string[]]$Apps=@('Edge','Chrome'))
 $ops=@();$items=@()
 foreach($target in @(Get-BnqqAppLiteCatalog|Where-Object App -in $Apps)){
  if(-not (Test-BnqqBrowserInstalled $target.App)){$items+=@([pscustomobject]@{App=$target.App;Name=$target.Name;Status='BrowserNotDetected'});continue}
  $machine=Get-RegSnapshot ($target.Path.Replace('HKCU:','HKLM:')) $target.Name
  if($machine.Existed){$status=if($machine.Kind -eq 'DWord' -and [long]$machine.Value -eq $target.Value){'AlreadySetByMachine'}else{'MachinePolicyConflict'};$items+=@([pscustomobject]@{App=$target.App;Name=$target.Name;Status=$status});continue}
  $before=Get-RegSnapshot $target.Path $target.Name
  if($before.Existed -and $before.Kind -ne 'DWord'){$items+=@([pscustomobject]@{App=$target.App;Name=$target.Name;Status='UnexpectedTypePreserved'});continue}
  if($before.Existed -and [long]$before.Value -eq $target.Value){$items+=@([pscustomobject]@{App=$target.App;Name=$target.Name;Status='AlreadySetLocally'});continue}
  $after=[pscustomobject]@{Path=$target.Path;Name=$target.Name;KeyExisted=$true;Existed=$true;Kind='DWord';Value=$target.Value}
  $ops+=@([pscustomobject]@{Before=$before;After=$after;Status='Prepared'})
  $items+=@([pscustomobject]@{App=$target.App;Name=$target.Name;Status='Candidate';RequestedValue=$target.Value})
 }
 [pscustomobject]@{Status='Preview';Items=$items;Operations=$ops;FpsGainProven=$false;BrowserPolicyAcceptance='NotVerified';Note='Edge: idle tabs after 5 minutes, background/startup off. Chrome: background when closed off. Machine policies preserved. MSA/profile restrictions may prevent Edge policy acceptance; check edge://policy. Voice/music apps untouched.'}
}
function Assert-BnqqAppLiteEntry {
 param($Entry)
 $target=@(Get-BnqqAppLiteCatalog|Where-Object {$_.Path -ceq $Entry.Before.Path -and $_.Name -ceq $Entry.Before.Name})
 if($target.Count -ne 1 -or $Entry.Before.Existed -isnot [bool] -or $Entry.Before.KeyExisted -isnot [bool]){throw 'Alvo de politica nao admitido'}
 if($Entry.Before.Existed -and ($Entry.Before.Kind -cne 'DWord' -or -not $Entry.Before.KeyExisted)){throw 'Original de politica invalido'}
 $expected=[pscustomobject]@{Path=$target[0].Path;Name=$target[0].Name;KeyExisted=$true;Existed=$true;Kind='DWord';Value=$target[0].Value}
 if(-not (Test-BnqqLiteSnapshot $expected $Entry.After)){throw 'Transicao de politica nao admitida'}
}
function Restore-BnqqAppLite {
 param([string]$File)
 if((Get-Item -LiteralPath $File -ErrorAction Stop).Length -gt 1048576){throw 'Journal grande demais'}
 $j=Get-Content -LiteralPath $File -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json
 if($j.Schema -cne 'BNQQ.AppLite.1' -or $j.Owner -cne (Get-BnqqOwner) -or @($j.Entries).Count -lt 1 -or @($j.Entries).Count -gt 5){throw 'Backup de politica invalido/outro usuario'}
 $seen=@{};foreach($e in $j.Entries){Assert-BnqqAppLiteEntry $e;$id=$e.Before.Path+'|'+$e.Before.Name;if($seen.ContainsKey($id)){throw 'Politica duplicada'};$seen[$id]=$true}
 $errors=@()
 foreach($e in $j.Entries){
  try{
   $current=Get-RegSnapshot $e.Before.Path $e.Before.Name
   if(Test-BnqqLiteSnapshot $current $e.Before){$e.Status='Restored'}
   elseif(Test-BnqqLiteSnapshot $current $e.After){Set-BnqqRegistrySnapshot $e.Before;if(-not (Test-BnqqLiteSnapshot (Get-RegSnapshot $e.Before.Path $e.Before.Name) $e.Before)){throw 'Restauracao nao verificada'};$e.Status='Restored'}
   else{throw ('Politica mudou externamente: '+$e.Before.Name)}
  }catch{$errors+=$_.Exception.Message}
  Write-BnqqAtomicJson $j $File
 }
 $j.Status=if($errors.Count){'NeedsRecovery'}else{'Restored'};Write-BnqqAtomicJson $j $File
 if($errors.Count){throw ($errors -join '; ')}
 [pscustomobject]@{Status='Restored';Backup=$File;RebootRequired=$false}
}
function Invoke-BnqqAppLite {
 param([ValidateSet('plan','apply','restore')][string]$Action='plan',[ValidateSet('Edge','Chrome')][string[]]$Apps=@('Edge','Chrome'),[string]$BackupFile)
 if($Action -eq 'restore'){$lock=Enter-BnqqStateLock;try{return (Restore-BnqqAppLite $BackupFile)}finally{$lock.Dispose()}}
 $plan=Get-BnqqAppLitePlan $Apps
 if($Action -eq 'plan'){return ($plan|Select-Object * -ExcludeProperty Operations)}
 $lock=Enter-BnqqStateLock;$file=$null
 try{
  foreach($f in @(Get-ChildItem -LiteralPath (Join-Path (Get-BnqqDataRoot) 'app-lite') -File -Filter '*.json' -ErrorAction SilentlyContinue)){$old=Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8|ConvertFrom-Json;if($old.Status -notin @('Applied','Restored')){throw ('Recupere primeiro: '+$f.FullName)}}
  if(-not $plan.Operations.Count){return [pscustomobject]@{Status='NoChanges';Items=$plan.Items;FpsGainProven=$false}}
  $file=Join-Path (Get-BnqqDataRoot) ('app-lite\'+[guid]::NewGuid().ToString('N')+'.json')
  $j=[pscustomobject]@{Schema='BNQQ.AppLite.1';Owner=(Get-BnqqOwner);Generated=[datetime]::UtcNow.ToString('o');Status='Prepared';Entries=$plan.Operations}
  Write-BnqqAtomicJson $j $file
  foreach($e in $j.Entries){Assert-BnqqAppLiteEntry $e;if((Get-RegSnapshot ($e.Before.Path.Replace('HKCU:','HKLM:')) $e.Before.Name).Existed){throw 'Politica de maquina apareceu durante preparacao'};if(-not (Test-BnqqLiteSnapshot (Get-RegSnapshot $e.Before.Path $e.Before.Name) $e.Before)){throw 'Politica mudou durante preparacao'};Set-BnqqRegistrySnapshot $e.After;if(-not (Test-BnqqLiteSnapshot (Get-RegSnapshot $e.Before.Path $e.Before.Name) $e.After)){throw 'Gravacao nao verificada'};$e.Status='Applied';Write-BnqqAtomicJson $j $file}
  $j.Status='Applied';Write-BnqqAtomicJson $j $file
  [pscustomobject]@{Status='Applied';Changed=$j.Entries.Count;Backup=$file;Items=$plan.Items;RegistryReadbackVerified=$true;BrowserPolicyAcceptance='NotVerified';FpsGainProven=$false;RebootRequired=$false}
 }catch{$failure=$_;if($file -and [IO.File]::Exists($file)){try{Restore-BnqqAppLite $file|Out-Null}catch{Write-BnqqNightLog 'APP-LITE-RECOVERY' $_.Exception.Message}};throw $failure}finally{$lock.Dispose()}
}
function Show-BnqqAppLiteMenu {
 Invoke-BnqqAppLite|Format-List
 Write-Host 'Politicas oficiais de Edge/Chrome, com backup. Discord: prefira movimento reduzido e desative overlay/clips somente se nao usar esses recursos. Nenhum cliente alternativo.'
 if((Read-Host 'Aplicar preferencias dos navegadores? Digite SIM') -ceq 'SIM'){Invoke-BnqqAppLite -Action apply|Format-List}
}
