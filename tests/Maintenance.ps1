#Requires -Version 5.1
# Real journal and task XML adapter; fake scheduler/SCM. No host service/task writes.
$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($n in @('Core','Maintenance')){. (Join-Path $script:BnqqRoot ('lib\'+$n+'.ps1'))}
if(-not ('Bnqq.SearchService' -as [type])){Add-Type -Path (Join-Path $script:BnqqRoot 'lib\SearchService.cs') -ErrorAction Stop}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-maint-'+[guid]::NewGuid().ToString('N'))
$script:BnqqDataRoot=$temp;$script:checks=0
function Check($ok,$text){if(-not $ok){throw $text};$script:checks++}
function MustThrow([scriptblock]$Code){$hit=$false;try{& $Code|Out-Null}catch{$hit=$true};Check $hit 'Expected refusal'}
function Reset {
 $script:enabled=$true;$script:running=$false;$script:idle=$false;$script:revision='original';$script:sets=0;$script:fail=$false;$script:startType='Automatic'
 $script:search=[pscustomobject]@{Name='WSearch';State=4;ConfigurationHash=('A'*64)}
}
function Get-ScheduledTask {
 param($TaskPath,$TaskName,$ErrorAction)
 [pscustomobject]@{TaskPath=$TaskPath;TaskName=$TaskName;State=$(if($script:running){'Running'}else{'Ready'});Settings=[pscustomobject]@{Enabled=$script:enabled;RunOnlyIfIdle=$script:idle}}
}
function Export-ScheduledTask {
 param($TaskPath,$TaskName,$ErrorAction)
 $enabled=if($script:enabled){''}else{'<Enabled>false</Enabled>'}
 '<Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><RegistrationInfo><URI>'+ $script:revision +'</URI></RegistrationInfo><Settings>'+ $enabled +'</Settings></Task>'
}
function AssertBackup {
 $disk=Get-Content -LiteralPath $script:journal.File -Raw|ConvertFrom-Json
 Check ($disk.Entries[-1].Status -in @('Prepared','Failed','Applied')) 'Write-ahead missing'
}
function Disable-ScheduledTask {
 param($InputObject,$ErrorAction)
 Check ($InputObject.TaskName -eq 'ScheduledDefrag') 'Wrong scheduler identity';AssertBackup
 $script:enabled=$false;$script:sets++
 if($script:fail){$script:fail=$false;throw 'Partial disable fixture'}
}
function Enable-ScheduledTask {param($InputObject,$ErrorAction);AssertBackup;$script:enabled=$true;$script:sets++}
function Get-BnqqSearchState {return ($script:search|Select-Object *)}
function Invoke-BnqqSearchControl {
 param($Running)
 AssertBackup;$script:sets++
 if($script:fail){$script:fail=$false;$script:search.State=3;throw 'Stop pending fixture'}
 $script:search.State=if($Running){4}else{1}
}
function Get-Service {param($Name,$ErrorAction);[pscustomobject]@{StartType=$script:startType;CanStop=$true}}
function NewTaskOp {
 $b=Get-BnqqTaskState ([pscustomobject]@{TaskPath='\Microsoft\Windows\Defrag\';TaskName='ScheduledDefrag'})
 $a=$b|Select-Object *;$a.Enabled=$false
 [pscustomobject]@{Kind='ScheduledTask';Before=$b;After=$a}
}
function NewServiceOp {$b=Get-BnqqSearchState;$a=$b|Select-Object *;$a.State=1;[pscustomobject]@{Kind='Service';Before=$b;After=$a}}
try{
 Reset;$op=NewTaskOp;$script:journal=New-BnqqJournal 'test';Invoke-BnqqJournalOperation $journal $op
 Check (-not $script:enabled) 'Task not deferred';Restore-BnqqJournal $journal.File|Out-Null
 Check $script:enabled 'Task not enabled';$writes=$script:sets;Restore-BnqqJournal $journal.File|Out-Null;Check ($writes -eq $script:sets) 'Restore not idempotent'
 Reset;$op=NewTaskOp;$script:journal=New-BnqqJournal 'test';$script:fail=$true;MustThrow {Invoke-BnqqJournalOperation $journal $op};Restore-BnqqJournal $journal.File|Out-Null;Check $script:enabled 'Partial task failure not restored'
 Reset;$op=NewTaskOp;$script:journal=New-BnqqJournal 'test';Invoke-BnqqJournalOperation $journal $op;$script:revision='external'
 MustThrow {Restore-BnqqJournal $journal.File};Check (-not $script:enabled) 'Foreign task definition overwritten'
 Reset;$op=NewTaskOp;$script:running=$true;$script:journal=New-BnqqJournal 'test';MustThrow {Invoke-BnqqJournalOperation $journal $op};Check ($script:sets -eq 0) 'Running task modified'
 Reset;$script:idle=$true;Check (@((Get-BnqqMaintenancePlan -DeferMaintenance).Operations).Count -eq 0) 'Already idle-only tasks redundantly tweaked'
 Reset;$script:enabled=$false;Check (@((Get-BnqqMaintenancePlan -DeferMaintenance).Operations).Count -eq 0) 'Disabled task re-enabled'
 Reset;$script:search.State=1;Check (@((Get-BnqqMaintenancePlan -PauseSearch).Operations).Count -eq 0) 'Stopped indexer changed'
 Reset;$script:startType='Disabled';Check (@((Get-BnqqMaintenancePlan -PauseSearch).Operations).Count -eq 0) 'Disabled running service cannot be restored without startup change'
 Reset;$op=NewServiceOp;$script:journal=New-BnqqJournal 'test';Invoke-BnqqJournalOperation $journal $op;Check ($script:search.State -eq 1) 'Indexer not stopped';Restore-BnqqJournal $journal.File|Out-Null;Check ($script:search.State -eq 4) 'Indexer not restarted'
 Reset;$op=NewServiceOp;$script:journal=New-BnqqJournal 'test';$script:fail=$true;MustThrow {Invoke-BnqqJournalOperation $journal $op};Restore-BnqqJournal $journal.File|Out-Null;Check ($script:search.State -eq 4) 'Pending stop not reconciled'
 Reset;$op=NewServiceOp;$script:journal=New-BnqqJournal 'test';Invoke-BnqqJournalOperation $journal $op;$script:search.ConfigurationHash='B'*64;MustThrow {Restore-BnqqJournal $journal.File};Check ($script:search.State -eq 1) 'Externally changed service overwritten'
 Reset;$op=NewServiceOp;$op.Before.Name='WinDefend';$op.After.Name='WinDefend';MustThrow {Assert-BnqqOperation $op}
 $op=NewTaskOp;$op.Before.TaskName='WindowsUpdate';$op.After.TaskName='WindowsUpdate';MustThrow {Assert-BnqqOperation $op}
 Reset;$op=NewTaskOp;$op.After.DefinitionHash='B'*64;MustThrow {Assert-BnqqOperation $op}
 Reset;$op=NewTaskOp;$op.After.Enabled=0;MustThrow {Assert-BnqqOperation $op}
 Reset;$op=NewTaskOp;$script:journal=New-BnqqJournal 'test';$journal.Data.Owner='foreign';Write-BnqqAtomicJson $journal.Data $journal.File;MustThrow {Restore-BnqqJournal $journal.File};Check ($script:sets -eq 0) 'Foreign owner mutated'
 ('PASS: maintenance '+$script:checks+' checks; temporary tasks, exact definitions, service transitions, pending writes, conflicts and rollback')
}finally{if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}}
