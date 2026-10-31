$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\RecoveryHub.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-recovery-'+[guid]::NewGuid().ToString('N'))
$script:BnqqDataRoot=$temp;$script:routed=''
function Check($ok,$message){if(-not $ok){throw $message}}
function MustThrow([scriptblock]$Code){$hit=$false;try{& $Code|Out-Null}catch{$hit=$true};Check $hit 'Expected refusal'}
function Test-BnqqAdmin {return $true}
function Restore-BnqqJournal {param($File);$script:routed='Windows'}
function Invoke-BnqqNicPolicy {param($Action,$File);Check ($Action -in @('restore','restore-active')) 'Wrong NIC action';$script:routed='NIC';$script:nicAction=$Action}
function Invoke-BnqqGpuProfile {param($Action,$File);Check ($Action -eq 'restore') 'Wrong GPU action';$script:routed='GPU'}
function Invoke-BnqqNetworkSession {param($Action,$File);Check ($Action -eq 'restore') 'Wrong network action';$script:routed='Network'}
function Invoke-BnqqGameSession {param($Action,$File);Check ($Action -eq 'restore') 'Wrong session action';$script:routed='Session'}
function Invoke-BnqqGameProfile {param($Directory,$Action,$BackupFile);Check ($Action -eq 'restore') 'Wrong profile action';$script:routed='Profile'}
function Invoke-BnqqFramePacing {param($Directory,$Action,$BackupFile);Check ($Action -eq 'restore') 'Wrong caps action';$script:routed='Caps'}
function Invoke-BnqqLegacyMigration {param($Action,$BackupFile);Check ($Action -eq 'restore') 'Wrong migration action';$script:routed='Migration'}
try {
 $cases=@(@('2','Windows','journals','unused'),@('BNQQ.Nic.1','NIC','nic-journals','unused'),@('BNQQ.Nvidia.1','GPU','nvidia-journals','unused'),@('BNQQ.NetworkSession.1','Network','network-sessions','unused'),@('BNQQ.Session.1','Session','sessions','unused'),@('BNQQ.GameProfile.1','Profile','gameprofiles','C:\fixture\cs2_video.txt'),@('BNQQ.FramePacing.1','Caps','framepacing','C:\fixture\cs2_machine_convars.vcfg'),@('BNQQ.LegacyIFEO.1','Migration','legacy-migrations','unused'))
 foreach($case in $cases){
  $file=Join-Path $temp ($case[2]+'\fixture.json')
  Write-BnqqAtomicJson @{Schema=$case[0];Owner=(Get-BnqqOwner);Status='Applied';File=$case[3]} $file
  $script:routed='';Invoke-BnqqRecovery $file
  Check ($script:routed -eq $case[1]) 'Wrong recovery adapter'
 }
 Check (@(Get-BnqqRecoveryCatalog).Count -eq 8) 'Catalog missing backup type'
 $activeNic=Join-Path $temp 'nic-journals\active.json'
 Write-BnqqAtomicJson @{Schema='BNQQ.Nic.1';Owner=(Get-BnqqOwner);Status='Activated'} $activeNic
 Invoke-BnqqRecovery $activeNic
 Check ($script:nicAction -eq 'restore-active') 'Activated NIC was restored only in registry'
 $processBackup=Join-Path $temp 'journals\cpu-only.json'
 Write-BnqqAtomicJson @{Schema=2;Owner=(Get-BnqqOwner);Entries=@(@{Kind='CpuSets'})} $processBackup
 function Test-BnqqAdmin {return $false}
 $script:routed='';Invoke-BnqqRecovery $processBackup
 Check ($script:routed -eq 'Windows') 'User CPU Sets recovery must not require admin preemptively'
 Write-BnqqAtomicJson @{Schema=2;Owner=(Get-BnqqOwner);Entries=@(@{Kind='BackgroundPriority'})} $processBackup
 $script:routed='';Invoke-BnqqRecovery $processBackup
 Check ($script:routed -eq 'Windows') 'User background-priority recovery must not require admin preemptively'
 Write-BnqqAtomicJson @{Schema=2;Owner=(Get-BnqqOwner);Entries=@(@{Kind='Power'})} $processBackup
 $script:routed='';MustThrow {Invoke-BnqqRecovery $processBackup};Check (-not $script:routed) 'Power recovery lost admin guard'
 function Test-BnqqAdmin {return $true}
 $file=Join-Path $temp 'sessions\invalid.json'
 Write-BnqqAtomicJson @{Schema='Legacy';Owner=(Get-BnqqOwner)} $file
 $script:routed='';MustThrow {Invoke-BnqqRecovery $file};Check (-not $script:routed) 'Unknown schema must not dispatch'
 Write-BnqqAtomicJson @{Schema='BNQQ.Session.1';Owner='wrong'} $file
 MustThrow {Invoke-BnqqRecovery $file}
 Write-BnqqAtomicJson @{Schema='BNQQ.GameProfile.1';Owner=(Get-BnqqOwner);File='C:\fixture\other.txt'} $file
 MustThrow {Invoke-BnqqRecovery $file}
 'PASS: recovery catalog, schema routing, owner refusal, target refusal and legacy refusal'
}finally{if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}}
