$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($n in @('Core','StorageMemory')){. (Join-Path $script:BnqqRoot ('lib\'+$n+'.ps1'))}
$native=Get-BnqqMemorySnapshot
if($native.PhysicalAvailableBytes -gt $native.PhysicalTotalBytes -or $native.CommitUsedBytes -gt $native.CommitLimitBytes){throw 'Invalid native memory counters'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-storage-'+[guid]::NewGuid().ToString('N'))
$script:BnqqDataRoot=$temp;$script:supported=$true;$script:qa=$true;$script:healthy=$true;$script:partial=$false;$script:writes=0
$script:pressure=$false
$script:states=@{}
foreach($id in @('fc95af4d-40e7-4b6d-835a-56d131dbc80e','dbc9e238-6de9-49e3-92cd-8c2b4946b472')){$script:states[$id]=[pscustomobject]@{Scheme='11111111-1111-1111-1111-111111111111';Sub='SUB_DISK';Setting=$id;AC=15;DC=100}}
function Check($ok,$message){if(-not $ok){throw $message}}
function MustThrow([scriptblock]$Code){$hit=$false;try{& $Code|Out-Null}catch{$hit=$true};Check $hit 'Expected refusal'}
function Get-BnqqMemorySnapshot {return [pscustomobject]@{PhysicalTotalBytes=32GB;PhysicalAvailableBytes=$(if($script:pressure){100MB}else{16GB});CommitUsedBytes=16GB;CommitLimitBytes=48GB}}
function Get-BnqqNvmeSupport {return [pscustomobject]@{Supported=$script:supported}}
function Get-BnqqPowerSnapshot {param($Scheme,$Setting);return ($script:states[$Setting]|Select-Object *)}
function Test-BnqqAdmin {return $true}
function Assert-BnqqHeavyQa {if(-not $script:qa){throw 'QA fixture refusal'}}
function Assert-BnqqPhaseHealth {param($Since);if(-not $script:healthy){throw 'WHEA fixture'}}
function Write-BnqqNightLog {param($Stage,$Message)}
function Set-BnqqOperationState {
 param($Op,$State)
 Assert-BnqqOperation $Op
 $disk=@(Get-ChildItem (Join-Path $temp 'journals') -Filter '*.json'|ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json}|Where-Object Status -ne 'Restored')
 Check ($disk.Count -eq 1 -and $disk[0].Entries.Count -gt 0) 'Missing durable power backup'
 $script:writes++;$script:states[$State.Setting]=$State|Select-Object *
 if($script:partial){$script:partial=$false;throw 'Failure after AC setting write'}
}
try {
 Check (-not (Get-BnqqMemoryReport).SeverePressure) 'Normal headroom misclassified'
 $script:pressure=$true;MustThrow {Assert-BnqqMemoryHeadroom};$script:pressure=$false
 $script:supported=$false;Check ((Get-BnqqNvmePlan).Status -eq 'Unsupported') 'Unsupported storage received a generic fallback';$script:supported=$true
 $p=Get-BnqqNvmePlan;Check ($p.Operations.Count -eq 2 -and $p.Operations[0].After.AC -eq 0 -and $p.Operations[0].After.DC -eq 100 -and $script:writes -eq 0) 'Plan/DC preservation failed'
 $script:qa=$false;MustThrow {Invoke-BnqqNvmePolicy -Action apply};Check ($script:writes -eq 0) 'QA guard wrote state';$script:qa=$true
 $script:pressure=$true;MustThrow {Invoke-BnqqNvmePolicy -Action apply};$script:pressure=$false
 $r=Invoke-BnqqNvmePolicy -Action apply
 Check ($r.Status -eq 'Applied' -and @($script:states.Values|Where-Object AC -ne 0).Count -eq 0) 'NVMe policy not applied'
 Restore-BnqqJournal $r.Journal|Out-Null
 Check (@($script:states.Values|Where-Object {$_.AC -ne 15 -or $_.DC -ne 100}).Count -eq 0) 'Original AC/DC not restored'
 $count=$script:writes;Restore-BnqqJournal $r.Journal|Out-Null;Check ($script:writes -eq $count) 'Recovery not idempotent'
 $script:partial=$true;MustThrow {Invoke-BnqqNvmePolicy -Action apply}
 Check (@($script:states.Values|Where-Object AC -ne 15).Count -eq 0) 'Partial write not recovered'
 $script:healthy=$false;MustThrow {Invoke-BnqqNvmePolicy -Action apply};$script:healthy=$true
 Check (@($script:states.Values|Where-Object AC -ne 15).Count -eq 0) 'WHEA did not rollback'
 $bad=$p.Operations[0]|ConvertTo-Json -Depth 5|ConvertFrom-Json;$bad.After.DC=0;MustThrow {Assert-BnqqOperation $bad}
 $bad.After.DC=100;$bad.Before.AC=60001;MustThrow {Assert-BnqqOperation $bad}
 $bad.Before.AC=15;$bad.Before.Setting='unapproved';MustThrow {Assert-BnqqOperation $bad}
 foreach($state in $script:states.Values){$state.AC=0}
 $script:qa=$false;Check ((Invoke-BnqqNvmePolicy -Action apply).Status -eq 'AlreadyConfigured') 'Already configured should not require another stress test'
 'PASS: native kernel memory, headroom guard, StorNVMe capability, exact GUIDs/ranges, AC/DC, no-op, write-ahead, partial failure, WHEA and idempotent rollback'
}finally{
 $full=[IO.Path]::GetFullPath($temp)
 if(-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
 if([IO.Directory]::Exists($full)){[IO.Directory]::Delete($full,$true)}
}
