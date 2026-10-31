$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\GameSession.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-session-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$script:BnqqDataRoot=$temp;$script:writes=0;$script:failAfterWrite=$false
$script:state=@{10=[pscustomobject]@{ProcessId=10;Name='cs2';StartTime='game-start';Priority='Normal'};20=[pscustomobject]@{ProcessId=20;Name='msedge';StartTime='browser-start';Priority='Normal'}}
function Check($ok,$message){if(-not $ok){throw $message}}
function MustThrow([scriptblock]$Code){$hit=$false;try{& $Code|Out-Null}catch{$hit=$true};Check $hit 'Expected refusal'}
function Get-Process {param($Name,$ErrorAction);if($Name -eq 'cs2'){return [pscustomobject]@{Id=10}};if($Name -eq 'msedge'){return [pscustomobject]@{Id=20}}}
function Get-BnqqSessionProcess {param([int]$ProcessId);if($script:state.ContainsKey($ProcessId)){return ($script:state[$ProcessId]|Select-Object *)}}
function Set-BnqqSessionPriority {
 param($ProcessId,$Priority,$Expected)
 $journals=@(Get-ChildItem (Join-Path $temp 'sessions') -Filter '*.json')
 Check ($journals.Count -eq 1) 'Journal must exist before mutation'
 $j=Get-Content $journals[0].FullName -Raw | ConvertFrom-Json
 Check (@($j.Entries|Where-Object ProcessId -eq $ProcessId).Count -eq 1) 'Entry must be durable before write'
 Check ($Expected.StartTime -eq $script:state[$ProcessId].StartTime) 'Identity passed to writer'
 $script:writes++;$script:state[$ProcessId].Priority=$Priority
 if($script:failAfterWrite){$script:failAfterWrite=$false;throw 'Injected interruption after priority write'}
}
$script:qaAllowed=$true
function Assert-BnqqHeavyQa {if(-not $script:qaAllowed){throw 'QA blocked fixture'}}
function Wait-BnqqSessionGame {param($Identity);Check ($script:state[20].Priority -eq 'BelowNormal') 'Browser not demoted during session';Check ($script:state[10].Priority -eq 'Normal') 'Game priority must remain unchanged'}
try {
 $script:qaAllowed=$false
 MustThrow {Invoke-BnqqGameSession -Action run -Apps msedge}
 Check ($script:writes -eq 0) 'QA refusal must not change priorities'
 $script:qaAllowed=$true
 MustThrow {Get-BnqqSessionPlan @('cs2')}
 MustThrow {Get-BnqqSessionPlan @('powershell')}
 $plan=Invoke-BnqqGameSession -Apps msedge
 Check ($plan.Participants.Count -eq 1 -and $script:writes -eq 0) 'Plan must not mutate'
 $r=Invoke-BnqqGameSession -Action run -Apps msedge
 Check ($r.Status -eq 'Restored' -and $script:state[20].Priority -eq 'Normal') 'Normal completion must restore'
 $j=Get-Content $r.Journal -Raw | ConvertFrom-Json
 Check ($j.Status -eq 'Restored') 'Final state durable'
 Restore-BnqqGameSession $r.Journal | Out-Null
 Check ($script:writes -eq 2) 'Restore idempotent'
 $j.Status='Active';$j.Entries[0].Status='Applied';$j.Entries[0].StartTime='old-process';Write-BnqqAtomicJson $j $r.Journal
 $script:state[20].Priority='BelowNormal';Restore-BnqqGameSession $r.Journal | Out-Null
 Check ($script:state[20].Priority -eq 'BelowNormal') 'Reused PID must never be changed'
 $j.Entries[0].StartTime='browser-start';$j.Entries[0].Status='Applied';Write-BnqqAtomicJson $j $r.Journal
 $script:state[20].Priority='AboveNormal';MustThrow {Restore-BnqqGameSession $r.Journal}
 Check ($script:state[20].Priority -eq 'AboveNormal') 'External priority must not be overwritten'
 $script:state[20].Priority='BelowNormal';Restore-BnqqGameSession $r.Journal | Out-Null
 $j.Entries[0].Name='cs2';Write-BnqqAtomicJson $j $r.Journal
 $before=$script:writes;MustThrow {Restore-BnqqGameSession $r.Journal};Check ($script:writes -eq $before) 'Invalid journal writes nothing'
 [IO.File]::Delete($r.Journal)
 $script:state[20].Priority='Normal';$script:failAfterWrite=$true
 MustThrow {Invoke-BnqqGameSession -Action run -Apps msedge}
 Check ($script:state[20].Priority -eq 'Normal') 'Partial failure must recover via prepared entry'
 'PASS: session planning, protected apps, write-ahead, completion, partial failure, PID reuse, conflicts and idempotent recovery'
}finally{[IO.Directory]::Delete($temp,$true)}
