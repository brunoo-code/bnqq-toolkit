#Requires -Version 5.1
# In-memory registry adapters; real temporary journals. Never changes host policies.
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\Core.ps1');. (Join-Path $root 'lib\AppLite.ps1')
$temp=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('bnqq-lite-test-'+[guid]::NewGuid().ToString('N'))));$script:BnqqDataRoot=$temp
$script:values=@{};$script:checks=0;$script:failOnce=$false;$script:writeCount=0
function Check($ok,$msg){if(-not $ok){throw $msg};$script:checks++}
function MustThrow([scriptblock]$s){$hit=$false;try{&$s|Out-Null}catch{$hit=$true};Check $hit 'Expected policy refusal'}
function Test-BnqqBrowserInstalled {param($App);return $true}
function Get-RegSnapshot {param($Path,$Name);$id=$Path+'|'+$Name;if($script:values.ContainsKey($id)){return ($script:values[$id]|Select-Object *)};[pscustomobject]@{Path=$Path;Name=$Name;KeyExisted=$false;Existed=$false;Kind=$null;Value=$null}}
function Set-BnqqRegistrySnapshot {param($Snapshot);$script:writeCount++;$j=Get-ChildItem (Join-Path $temp 'app-lite') -File -Filter '*.json'|Sort-Object LastWriteTime -Descending|Select-Object -First 1;Check (@((Get-Content $j.FullName -Raw|ConvertFrom-Json).Entries).Count -eq 5) 'All originals not durable before policy write';$id=$Snapshot.Path+'|'+$Snapshot.Name;if($Snapshot.Existed){$script:values[$id]=$Snapshot|Select-Object *}else{$script:values.Remove($id)};if($script:failOnce -and $Snapshot.Name -eq 'SleepingTabsEnabled'){$script:failOnce=$false;throw 'Injected policy interruption'}}
function Write-BnqqNightLog {param($Stage,$Message)}
try{
 $p=Invoke-BnqqAppLite;Check ($p.Items.Count -eq 5 -and $script:writeCount -eq 0) 'Preview mutated policies'
 $a=Invoke-BnqqAppLite -Action apply;Check ($a.Changed -eq 5 -and $a.RegistryReadbackVerified -and $a.BrowserPolicyAcceptance -eq 'NotVerified') 'False browser acceptance or missing registry readback'
 $hash=(Get-FileHash $a.Backup).Hash;$again=Invoke-BnqqAppLite -Action apply
 Check ($again.Status -eq 'NoChanges' -and (Get-FileHash $a.Backup).Hash -ceq $hash) 'Idempotence overwrote backup'
 Invoke-BnqqAppLite -Action restore -BackupFile $a.Backup|Out-Null;Check ($script:values.Count -eq 0) 'Absent originals not restored'
 Invoke-BnqqAppLite -Action restore -BackupFile $a.Backup|Out-Null
 $script:failOnce=$true;MustThrow {Invoke-BnqqAppLite -Action apply};Check ($script:values.Count -eq 0) 'Partial policy application not rolled back'
 $a=Invoke-BnqqAppLite -Action apply;$key='HKCU:\Software\Policies\Microsoft\Edge|SleepingTabsTimeout';$script:values[$key].Value=900
 MustThrow {Invoke-BnqqAppLite -Action restore -BackupFile $a.Backup}
 Check ($script:values[$key].Value -eq 900 -and $script:values.Count -eq 1) 'External policy overwritten or other originals not recovered'
 MustThrow {Invoke-BnqqAppLite -Action apply}
 $script:values[$key].Value=300;Invoke-BnqqAppLite -Action restore -BackupFile $a.Backup|Out-Null
 $machine=[pscustomobject]@{Path='HKLM:\Software\Policies\Microsoft\Edge';Name='BackgroundModeEnabled';KeyExisted=$true;Existed=$true;Kind='DWord';Value=1};$script:values[$machine.Path+'|'+$machine.Name]=$machine
 Check (@((Invoke-BnqqAppLite).Items|Where-Object Status -eq 'MachinePolicyConflict').Count -eq 1) 'Machine conflict not preserved'
 $bad=[pscustomobject]@{Before=[pscustomobject]@{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';Name='SleepingTabsTimeout';KeyExisted=$false;Existed=$false};After=@{}}
 MustThrow {Assert-BnqqAppLiteEntry $bad}
 $j=Get-Content $a.Backup -Raw|ConvertFrom-Json;$j.Owner='someone-else';Write-BnqqAtomicJson $j $a.Backup
 MustThrow {Invoke-BnqqAppLite -Action restore -BackupFile $a.Backup}
 "PASS: app lite $script:checks checks; durable batch, registry readback, immutable backups, partial failure, conflict preservation, ownership, strict policy scope"
}finally{
 $allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath());if(-not $temp.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $temp -Leaf) -notlike 'bnqq-lite-test-*'){throw 'Unsafe fixture cleanup'}
 if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
}
