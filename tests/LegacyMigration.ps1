$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\LegacyMigration.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-migration-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$script:BnqqDataRoot=Join-Path $temp 'data';$script:state=@{};$script:writes=0;$script:qa=$true;$script:failAfterWrite=$false
function Key($Path,$Name){return ($Path+'|'+$Name).ToLowerInvariant()}
function Check($ok,$message){if(-not $ok){throw $message}}
function MustThrow([scriptblock]$Code){$hit=$false;try{& $Code|Out-Null}catch{$hit=$true};Check $hit 'Expected refusal'}
function Test-BnqqAdmin {return $true}
function Assert-BnqqHeavyQa {if(-not $script:qa){throw 'QA blocked fixture'}}
function Get-RegSnapshot {param($Path,$Name);return ($script:state[(Key $Path $Name)]|Select-Object *)}
function Set-BnqqRegistrySnapshot {
 param($Snapshot)
 $found=$false
 foreach($f in @(Get-ChildItem (Join-Path $script:BnqqDataRoot 'legacy-migrations') -Filter '*.json')){
  $j=Get-Content $f.FullName -Raw|ConvertFrom-Json
  if(@($j.Entries|Where-Object {$_.Before.Path -eq $Snapshot.Path -and $_.Before.Name -eq $Snapshot.Name -and $_.Status -in @('Prepared','Applied')}).Count){$found=$true}
 }
 Check $found 'Write must have durable journal entry'
 $script:writes++;$script:state[(Key $Snapshot.Path $Snapshot.Name)]=$Snapshot|Select-Object *
 if($script:failAfterWrite){$script:failAfterWrite=$false;throw 'Injected interruption after removal'}
}
try {
 $targets=@(Get-BnqqLegacyTargets)
 $original=@(foreach($t in $targets){$script:state[(Key $t.Path $t.Name)]=[pscustomobject]@{Path=$t.Path;Name=$t.Name;KeyExisted=$true;Existed=$true;Kind='DWord';Value=$t.LegacyValue};[pscustomobject]@{Path=$t.Path.Replace('\','\\');Name=$t.Name;Existed=$false;Kind=$null;Value=$null}})
 $old=Join-Path $temp 'old.json';$new=Join-Path $temp 'new.json'
 Write-BnqqAtomicJson @{Created='2020-01-01T00:00:00Z';Entries=$original} $old
 Write-BnqqAtomicJson @{Created='2021-01-01T00:00:00Z';Entries=@($script:state.Values)} $new
 $plan=@(Get-BnqqLegacyMigrationPlan @($new,$old))
 Check ($plan.Count -eq 6 -and @($plan|Where-Object Action -eq 'RemoveKnownOverride').Count -eq 6) 'Earliest snapshot must be selected per target'
 Check ($script:writes -eq 0) 'Plan must not mutate'
 $script:qa=$false;MustThrow {Invoke-BnqqLegacyMigration -Action apply -Files $old};Check ($script:writes -eq 0) 'QA refusal must not write';$script:qa=$true
 $script:state[(Key $targets[0].Path $targets[0].Name)].Value=2
 MustThrow {Invoke-BnqqLegacyMigration -Action apply -Files $old};Check ($script:writes -eq 0) 'Conflict must prevent whole batch'
 $script:state[(Key $targets[0].Path $targets[0].Name)].Value=3
 $r=Invoke-BnqqLegacyMigration -Action apply -Files @($new,$old)
 Check ($r.Removed -eq 6 -and @($script:state.Values|Where-Object Existed).Count -eq 0) 'Known overrides not removed'
 Check (@($script:state.Values|Where-Object {-not $_.KeyExisted}).Count -eq 0) 'Unknown original key existence must never trigger key deletion'
 Restore-BnqqLegacyMigration $r.Backup | Out-Null
 Check (@($script:state.Values|Where-Object Existed).Count -eq 6) 'Undo must restore all original overrides'
 $count=$script:writes;Restore-BnqqLegacyMigration $r.Backup|Out-Null;Check ($script:writes -eq $count) 'Undo idempotent'
 $script:failAfterWrite=$true;MustThrow {Invoke-BnqqLegacyMigration -Action apply -Files $old}
 Check (@($script:state.Values|Where-Object Existed).Count -eq 6) 'Partial failure must undo removal'
 $duplicate=Join-Path $temp 'duplicate.json';Write-BnqqAtomicJson @{Created='2020-01-01T00:00:00Z';Entries=@($original[0],$original[0])} $duplicate
 MustThrow {Get-BnqqLegacyMigrationPlan $duplicate}
 $invalid=Join-Path $temp 'invalid.json';Write-BnqqAtomicJson @{Created='2020-01-01T00:00:00Z';Entries=@(@{Path=$targets[0].Path;Name=$targets[0].Name;Existed='false'})} $invalid
 Check (@(Get-BnqqLegacyMigrationPlan $invalid)[0].Action -eq 'InvalidOriginal') 'String false must not authorize deletion'
 $j=Get-Content $r.Backup -Raw|ConvertFrom-Json;$j.Entries[0].Before.Path='HKLM:\SOFTWARE\Unapproved';Write-BnqqAtomicJson $j $r.Backup
 $count=$script:writes;MustThrow {Restore-BnqqLegacyMigration $r.Backup};Check ($script:writes -eq $count) 'Tampered journal must not write'
 'PASS: migration chronology, scope, source flags, preview, QA, conflicts, write-ahead, rollback, idempotence and tamper refusal'
}finally{[IO.Directory]::Delete($temp,$true)}
