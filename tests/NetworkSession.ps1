$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\NetworkSession.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-network-'+[guid]::NewGuid().ToString('N'))
$script:BnqqDataRoot=$temp;$script:policies=@();$script:writes=0;$script:qa=$true;$script:admin=$true;$script:failure=$false;$script:foreign=$false;$script:expectedApps=1
function Check($ok,$message){if(-not $ok){throw $message}}
function MustThrow([scriptblock]$Code){$caught=$false;try{& $Code|Out-Null}catch{$caught=$true};Check $caught 'Expected refusal'}
function Test-BnqqAdmin {return $script:admin}
function Assert-BnqqHeavyQa {if(-not $script:qa){throw 'QA fixture refusal'}}
function Get-Process {param($Name,$ErrorAction);return [pscustomobject]@{Id=10}}
function Get-BnqqSessionProcess {param($ProcessId);return [pscustomobject]@{ProcessId=10;Name='cs2';StartTime='fixed-game';Priority='Normal'}}
function Get-BnqqNetPolicies {return $script:policies}
function Add-BnqqNetPolicy {
 param($Expected)
 $disk=@(Get-ChildItem (Join-Path $temp 'network-sessions') -Filter '*.json'|ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json}|Where-Object Status -ne 'Restored')
 Check ($disk.Count -eq 1 -and $disk[0].Entries[-1].Status -eq 'Prepared') 'Missing write-ahead before creation'
 Check (Test-BnqqSameValue $Expected $disk[0].Entries[-1].Expected) 'Incorrect durable expected state'
 $script:writes++;$script:policies+=@($Expected|Select-Object *)
 if($script:failure){$script:failure=$false;throw 'Injected failure after native creation'}
}
function Remove-BnqqNetPolicy {
 param($Name)
 Check ($Name -cmatch '^bnqq-net-[0-9a-f]{32}-[0-2]$') 'Broad deletion forbidden'
 $script:writes++;$script:policies=@($script:policies|Where-Object Name -ine $Name)
}
function Wait-BnqqSessionGame {
 param($Identity)
 Check ($Identity.StartTime -eq 'fixed-game') 'Missing fixed game identity'
 $own=@($script:policies|Where-Object Name -like 'bnqq-net-*')
 Check ($own.Count -eq $script:expectedApps -and @($own|Where-Object ThrottleRateAction -ne 512000).Count -eq 0) 'Missing actual session policies'
 if($script:foreign){$own[0].DSCPAction=10}
}
try {
 $p=Invoke-BnqqNetworkSession -Apps @('OneDrive.exe','onedrive.exe')
 Check ($p.Apps.Count -eq 1 -and $p.RateBitsPerSecond -eq 512000 -and $script:writes -eq 0) 'Plan units, deduplication or no-write broken'
 MustThrow {Invoke-BnqqNetworkSession -Apps cs2.exe}
 MustThrow {Invoke-BnqqNetworkSession -Apps '*'}
 MustThrow {Invoke-BnqqNetworkSession -UploadKbps 1}
 MustThrow {Invoke-BnqqNetworkSession -Action run}
 $script:qa=$false;MustThrow {Invoke-BnqqNetworkSession -Action run -Apps OneDrive.exe};$script:qa=$true
 $script:admin=$false;MustThrow {Invoke-BnqqNetworkSession -Action run -Apps OneDrive.exe};$script:admin=$true
 Check ($script:writes -eq 0) 'Guard wrote a policy'
 $script:policies=@([pscustomobject]@{Name='game-dscp';AppPathNameMatchCondition='cs2.exe'})
 $r=Invoke-BnqqNetworkSession -Action run -Apps OneDrive.exe
 Check ($r.Status -eq 'Restored' -and $script:policies.Count -eq 1 -and $script:policies[0].Name -eq 'game-dscp') 'Completion changed unrelated policy'
 $script:expectedApps=3
 $multi=Invoke-BnqqNetworkSession -Action run -Apps (Get-BnqqNetworkApps)
 Check ($multi.Apps.Count -eq 3 -and $script:policies.Count -eq 1) 'Multiple app restoration incomplete'
 $script:expectedApps=1
 $native=New-BnqqNetExpectedState 'bnqq-net-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-0' 'OneDrive.exe' 512000
 $normalized=$native|Select-Object *;$normalized.Name=$normalized.Name.ToUpperInvariant();$normalized.AppPathNameMatchCondition='ONEDRIVE.EXE';$normalized.IPSrcPrefixMatchCondition=$null
 Check (Test-BnqqSameValue $native (Get-BnqqNetState $normalized)) 'Provider case/null normalization broken'
 $count=$script:writes;Restore-BnqqNetworkSession $r.Journal|Out-Null
 Check ($script:writes -eq $count) 'Recovery not idempotent'
 foreach($app in @('OneDrive.exe','C:\Apps\OneDrive.exe','*','')){
  $script:policies=@([pscustomobject]@{Name='foreign';AppPathNameMatchCondition=$app})
  MustThrow {Invoke-BnqqNetworkSession -Action run -Apps OneDrive.exe}
  Check ($script:writes -eq $count) 'Overlap caused mutation'
 }
 $script:policies=@();$script:failure=$true
 MustThrow {Invoke-BnqqNetworkSession -Action run -Apps OneDrive.exe}
 Check ($script:policies.Count -eq 0) 'Failure after write did not recover prepared entry'
 $script:foreign=$true
 MustThrow {Invoke-BnqqNetworkSession -Action run -Apps OneDrive.exe}
 Check ($script:policies.Count -eq 1 -and $script:policies[0].DSCPAction -eq 10) 'External action overwritten'
 $pending=@(Get-ChildItem (Join-Path $temp 'network-sessions') -Filter '*.json'|Where-Object {(Get-Content $_.FullName -Raw|ConvertFrom-Json).Status -eq 'NeedsRecovery'})[0].FullName
 $count=$script:writes;MustThrow {Invoke-BnqqNetworkSession -Action run -Apps Dropbox.exe}
 Check ($script:writes -eq $count) 'Pending session ignored'
 $j=Get-Content $pending -Raw|ConvertFrom-Json;$j.Entries[0].Expected.AppPathNameMatchCondition='cs2.exe';Write-BnqqAtomicJson $j $pending
 MustThrow {Restore-BnqqNetworkSession $pending};Check ($script:writes -eq $count) 'Tampered journal deleted a policy'
 $j.Entries[0].Expected.AppPathNameMatchCondition='onedrive.exe';Write-BnqqAtomicJson $j $pending
 $script:policies[0].DSCPAction=-1;$script:qa=$false
 $script:policies[0].IPDstPortStartMatchCondition=443
 MustThrow {Restore-BnqqNetworkSession $pending};Check ($script:writes -eq $count) 'External selector overwritten'
 $script:policies[0].IPDstPortStartMatchCondition=0
 # Recovery remains available despite an expired/failed certificate.
 Invoke-BnqqNetworkSession -Action restore -File $pending|Out-Null
 Check ($script:policies.Count -eq 0) 'Recovery required QA'
 # Reboot/absent ActiveStore policy is an idempotent restore, not a reset.
 $j.Status='Active';$j.Entries[0].Status='Prepared';Write-BnqqAtomicJson $j $pending
 Restore-BnqqNetworkSession $pending|Out-Null
 'PASS: outbound session units, allowlist, admin/QA, overlap, write-ahead, completion, partial failure, tampering, external conflict, recovery and reboot absence'
}finally{if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}}
