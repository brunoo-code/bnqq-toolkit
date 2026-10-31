#Requires -Version 5.1
# Real journal files; registry and signature adapters are fixtures. No app/startup changes.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
foreach($file in @('Core','Startup')){. (Join-Path $repo ('lib\'+$file+'.ps1'))}
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temp=[IO.Path]::GetFullPath((Join-Path $base ('bnqq-startup-'+[guid]::NewGuid().ToString('N'))))
if(-not $temp.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture path'}
$script:BnqqDataRoot=$temp;$script:checks=0
function Check($ok,$message){if(-not $ok){throw $message};$script:checks++}
function MustThrow([scriptblock]$code){$hit=$false;try{& $code|Out-Null}catch{$hit=$true};Check $hit 'Expected startup rejection'}
function Reset-Fixture {
 if([IO.Directory]::Exists($temp)){
  if([IO.Path]::GetFullPath($temp) -ne $temp -or -not $temp.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe reset'}
  [IO.Directory]::Delete($temp,$true)
 }
 $script:commands=@{Spotify='C:\Music Player\Spotify.exe --launch-background';RobloxPlayerBeta='"%LOCALAPPDATA%\Roblox\Versions\fixture\RobloxPlayerBeta.exe" --background';Discord='keep voice startup'}
 $script:original=$script:commands.Clone();$script:writes=0;$script:signed=$true;$script:partial=$false
}
function Get-RegSnapshot {
 param([string]$Path,[string]$Name)
 [pscustomobject]@{Path=$Path;Name=$Name;KeyExisted=$true;Existed=$script:commands.ContainsKey($Name);Kind=$(if($script:commands.ContainsKey($Name)){'String'}else{$null});Value=$script:commands[$Name]}
}
function Get-BnqqStartupSignature {param($File,$Publisher);return $script:signed}
function Set-BnqqRegistrySnapshot {
 param($Snapshot)
 if(-not $Snapshot.Existed){
  $file=Get-ChildItem (Join-Path $temp 'journals') -Filter '*.json'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
  $disk=Get-Content $file.FullName -Raw|ConvertFrom-Json
  $prepared=@($disk.Entries|Where-Object {$_.Before.Name -ceq $Snapshot.Name -and $_.Status -ceq 'Prepared'})
  Check ($prepared.Count -eq 1 -and $prepared[0].Before.Value -ceq $script:original[$Snapshot.Name]) 'Original not durable before startup removal'
  $script:commands.Remove($Snapshot.Name)
 }else{$script:commands[$Snapshot.Name]=$Snapshot.Value}
 $script:writes++
 if($script:partial -and -not $Snapshot.Existed -and $Snapshot.Name -ceq 'RobloxPlayerBeta'){$script:partial=$false;throw 'Partial removal fixture'}
}
try{
 Reset-Fixture
 $plan=Get-BnqqStartupPlan
 Check ($plan.Operations.Count -eq 2 -and $script:writes -eq 0) 'Preview mutated registry or missed targets'
 Check ([IO.Path]::GetFileName((Get-BnqqStartupExecutable $script:original.Spotify)) -ceq 'Spotify.exe') 'Unquoted path with spaces not recognized'
 MustThrow {Invoke-BnqqStartup -Action apply}
 MustThrow {Invoke-BnqqStartup -Action apply -Apps Discord}
 foreach($protected in @('RiotClient','RiotVanguard','vgc','vgk','FACEIT','SecurityHealth')){MustThrow {Invoke-BnqqStartup -Action apply -Apps $protected}}
 Check ($script:writes -eq 0) 'Protected startup target reached registry writes'
 $result=Invoke-BnqqStartup -Action apply -Apps Spotify,RobloxPlayerBeta
 Check ($result.Changed -eq 2 -and $script:commands.Count -eq 1 -and $script:commands.Discord -ceq 'keep voice startup') 'Startup scope exceeded selected apps'
 Check ((Split-Path (Split-Path $result.Journal -Parent) -Leaf) -ceq 'startup-journals') 'Persistent backup not archived'
 Assert-BnqqNoPendingJournal
 $hash=(Get-FileHash $result.Journal -Algorithm SHA256).Hash
 $again=Invoke-BnqqStartup -Action apply -Apps Spotify,RobloxPlayerBeta
 Check ($again.Status -ceq 'AlreadyConfigured' -and (Get-FileHash $result.Journal -Algorithm SHA256).Hash -ceq $hash) 'Idempotent apply overwrote original backup'
 Invoke-BnqqStartup -Action restore -File $result.Journal|Out-Null
 Check ($script:commands.Spotify -ceq $script:original.Spotify -and $script:commands.RobloxPlayerBeta -ceq $script:original.RobloxPlayerBeta) 'Original commands not restored exactly'
 $before=$script:writes;Invoke-BnqqStartup -Action restore -File $result.Journal|Out-Null
 Check ($script:writes -eq $before) 'Restore not idempotent'
 Reset-Fixture
 $first=Invoke-BnqqStartup -Action apply -Apps RobloxPlayerBeta
 $second=Invoke-BnqqStartup -Action apply -Apps Spotify
 Check ($first.Journal -cne $second.Journal -and (Test-Path -LiteralPath $first.Journal) -and (Test-Path -LiteralPath $second.Journal)) 'Independent persistent preference blocked or overwrote backup'
 Assert-BnqqNoPendingJournal
 Invoke-BnqqStartup -Action restore -File $second.Journal|Out-Null
 Invoke-BnqqStartup -Action restore -File $first.Journal|Out-Null
 Check ($script:commands.Spotify -ceq $script:original.Spotify -and $script:commands.RobloxPlayerBeta -ceq $script:original.RobloxPlayerBeta) 'Independent preference originals not recovered'
 Reset-Fixture;$script:signed=$false
 MustThrow {Invoke-BnqqStartup -Action apply -Apps Spotify}
 Check ($script:writes -eq 0) 'Unverified publisher reached registry writes'
 Reset-Fixture;$script:commands.Spotify='C:\Windows\System32\cmd.exe /c anything'
 MustThrow {Invoke-BnqqStartup -Action apply -Apps Spotify}
 Check ($script:writes -eq 0) 'Unexpected executable reached registry writes'
 Reset-Fixture;$script:partial=$true
 MustThrow {Invoke-BnqqStartup -Action apply -Apps Spotify,RobloxPlayerBeta}
 Check ($script:commands.Spotify -ceq $script:original.Spotify -and $script:commands.RobloxPlayerBeta -ceq $script:original.RobloxPlayerBeta) 'Partial deletion did not recover originals'
 Reset-Fixture;$result=Invoke-BnqqStartup -Action apply -Apps Spotify,RobloxPlayerBeta
 $script:commands.Spotify=$script:original.Spotify+' --external'
 MustThrow {Invoke-BnqqStartup -Action restore -File $result.Journal}
 Check ($script:commands.Spotify.EndsWith('--external') -and $script:commands.RobloxPlayerBeta -ceq $script:original.RobloxPlayerBeta) 'Rollback overwrote external state or missed independent entry'
 Reset-Fixture;$plan=Get-BnqqStartupPlan -Apps Spotify;$bad=$plan.Operations[0];$bad.Before.Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
 MustThrow {Assert-BnqqStartupOperation $bad}
 "PASS: startup $script:checks checks; exact commands, publishers, durable originals, idempotence, partial failures and conflicts"
}finally{
 if([IO.Path]::GetFullPath($temp) -ne $temp -or -not $temp.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
 if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
}
