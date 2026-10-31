#Requires -Version 5.1
# Self queries plus priority/rollback on an owned stdin-waiting helper only. No game/stress.
$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($n in @('Core','ProcessSampling','BackgroundBudget')){. (Join-Path $script:BnqqRoot ('lib\'+$n+'.ps1'))}
$checks=0
function Check($ok,$message){if(-not $ok){throw $message};$script:checks++}
function MustThrow([scriptblock]$code){$hit=$false;try{& $code|Out-Null}catch{$hit=$true};Check $hit 'Expected rejection'}
Initialize-BnqqProcessSampler
$self=[Diagnostics.Process]::GetCurrentProcess();$watch=$null
try{
 $identity=[pscustomobject]@{ProcessId=$PID;Name=$self.ProcessName;StartTime=$self.StartTime.ToUniversalTime().ToString('o')}
 $watch=New-BnqqFocusGameWatch $identity
 Check ($watch -and (Test-BnqqFocusGameWatchAlive $watch)) 'Live self not observed'
 Check (Test-BnqqFocusGameWatchAlive $watch) 'Repeated wait lost process'
 Check ($null -eq [Bnqq.TelemetryV3.ProcessTelemetry]::Watch($PID,$identity.Name,'wrong-start',(Get-BnqqOwner),[uint32]$self.SessionId)) 'Reused PID identity admitted'
 Check ($null -eq [Bnqq.TelemetryV3.ProcessTelemetry]::Watch($PID,'wrong-name',$identity.StartTime,(Get-BnqqOwner),[uint32]$self.SessionId)) 'Different image admitted'
 MustThrow {[Bnqq.TelemetryV3.ProcessTelemetry]::Watch($PID,$identity.Name,$identity.StartTime,'S-1-0-0',[uint32]$self.SessionId)}
 MustThrow {[Bnqq.TelemetryV3.ProcessTelemetry]::Watch($PID,$identity.Name,$identity.StartTime,(Get-BnqqOwner),[uint32]($self.SessionId+1))}
 $watch.Dispose();$watch.Dispose()
 MustThrow {Test-BnqqFocusGameWatchAlive $watch}
 MustThrow {Get-BnqqBudgetState $PID}
}finally{if($watch){$watch.Dispose()};$self.Dispose()}
$tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temp=[IO.Path]::GetFullPath((Join-Path $tempBase ('bnqq-lifetime-'+[guid]::NewGuid().ToString('N'))))
if(-not $temp.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture path outside temp'}
[void][IO.Directory]::CreateDirectory($temp)
$script:BnqqDataRoot=Join-Path $temp 'data'
$child=$null;$watch=$null
try{
 $exe=Join-Path $temp 'msedge.exe'
 Add-Type -TypeDefinition 'public static class BnqqLifetimeFixture { public static void Main(){System.Console.ReadLine();} }' -OutputAssembly $exe -OutputType ConsoleApplication
 $start=New-Object Diagnostics.ProcessStartInfo
 $start.FileName=$exe;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WindowStyle='Hidden';$start.RedirectStandardInput=$true
 $child=[Diagnostics.Process]::Start($start)
 $identity=[pscustomobject]@{ProcessId=$child.Id;Name=$child.ProcessName;StartTime=$child.StartTime.ToUniversalTime().ToString('o')}
 $watch=New-BnqqFocusGameWatch $identity
 Check ($watch -and (Test-BnqqFocusGameWatchAlive $watch)) 'Owned helper not observed'
 $priority=Get-BnqqBudgetState $child.Id
 Check ($priority.Name -ceq 'msedge' -and $priority.StartTime -ceq $identity.StartTime -and $priority.Priority -ceq $child.PriorityClass.ToString()) 'Production budget getter differs from owned helper'
 $wrong=$priority|Select-Object *;$wrong.StartTime='replacement'
 Check ($null -eq (Get-BnqqBudgetState $child.Id $wrong)) 'Budget getter accepted another creation time'
 $after=$priority|Select-Object *;$after.Priority='BelowNormal'
 MustThrow {[Bnqq.TelemetryV3.ProcessTelemetry]::SetBackgroundPriority($child.Id,'cs2',$priority.StartTime,$priority.Priority,'BelowNormal',(Get-BnqqOwner),$script:BnqqSamplerScope.Session)}
 MustThrow {[Bnqq.TelemetryV3.ProcessTelemetry]::SetBackgroundPriority($child.Id,$priority.Name,'wrong-start',$priority.Priority,'BelowNormal',(Get-BnqqOwner),$script:BnqqSamplerScope.Session)}
 MustThrow {[Bnqq.TelemetryV3.ProcessTelemetry]::SetBackgroundPriority($child.Id,$priority.Name,$priority.StartTime,$priority.Priority,'BelowNormal','S-1-0-0',$script:BnqqSamplerScope.Session)}
 MustThrow {[Bnqq.TelemetryV3.ProcessTelemetry]::SetBackgroundPriority($child.Id,$priority.Name,$priority.StartTime,$priority.Priority,'BelowNormal',(Get-BnqqOwner),($script:BnqqSamplerScope.Session+1))}
 MustThrow {[Bnqq.TelemetryV3.ProcessTelemetry]::SetBackgroundPriority($child.Id,$priority.Name,$priority.StartTime,$priority.Priority,'RealTime',(Get-BnqqOwner),$script:BnqqSamplerScope.Session)}
 $stale=$priority|Select-Object *;$stale.Priority=if($priority.Priority -ceq 'High'){'Normal'}else{'High'}
 MustThrow {Set-BnqqBudgetState $after $stale}
 Check ((Get-BnqqBudgetState $child.Id).Priority -ceq $priority.Priority) 'Rejected native write changed helper priority'
 $journal=New-BnqqJournal 'owned-helper-native-priority'
 Invoke-BnqqJournalOperation $journal ([pscustomobject]@{Kind='BackgroundPriority';Before=$priority;After=$after})
 Check ((Get-BnqqBudgetState $child.Id).Priority -ceq 'BelowNormal') 'Native priority application failed'
 Restore-BnqqJournal $journal.File|Out-Null
 Check ((Get-BnqqBudgetState $child.Id).Priority -ceq $priority.Priority) 'Native priority rollback lost original value'
 $child.StandardInput.Close()
 Check ($child.WaitForExit(5000)) 'Owned helper did not exit cooperatively'
 Check (-not (Test-BnqqFocusGameWatchAlive $watch)) 'Exited process reported alive'
 Check (-not (Test-BnqqFocusGameWatchAlive $watch)) 'Exited handle changed back to alive'
 Check ($null -eq (Get-BnqqBudgetState $child.Id $priority)) 'Budget getter retained exited helper while its handle remained open'
}finally{
 try{if($child){try{$child.StandardInput.Close();if(-not $child.WaitForExit(5000)){throw 'Helper still running'}}finally{$child.Dispose()}}}
 finally{
  if($watch){$watch.Dispose()}
  if([IO.Path]::GetFullPath($temp) -ne $temp -or -not $temp.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase)){throw 'Cleanup path changed'}
  if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
 }
}
"PASS: process lifetime $checks checks; scope, creation identity, nonblocking wait, exit and disposal"
