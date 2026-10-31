#Requires -Version 5.1
# Native checks read only this test process. Enumeration/busy-app fixtures are mocked.
$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($n in @('Core','CpuSession','ProcessSampling')){. (Join-Path $script:BnqqRoot ('lib\'+$n+'.ps1'))}
$checks=0
function Check($ok,$message){if(-not $ok){throw $message};$script:checks++}
function MustThrow([scriptblock]$code){$hit=$false;try{& $code|Out-Null}catch{$hit=$true};Check $hit 'Expected rejection'}
# CLR types survive CLI script invocations: a loaded V1 must not block V2.
Add-Type 'namespace Bnqq { public static class ProcessTelemetry { public const int Contract=1; } } namespace Bnqq.TelemetryV2 { public static class ProcessTelemetry { public const int Contract=2; } }'
Initialize-BnqqProcessSampler
Check ($null -ne ('Bnqq.ProcessTelemetry' -as [type]) -and $null -ne ('Bnqq.TelemetryV2.ProcessTelemetry' -as [type]) -and $script:BnqqSamplerContract -ceq 'TelemetryV3') 'Loaded legacy contracts blocked current sampler'
$self=[Diagnostics.Process]::GetCurrentProcess()
try{
 $sample=[Bnqq.TelemetryV3.ProcessTelemetry]::Read($PID,$self.ProcessName,(Get-BnqqOwner),[uint32]$self.SessionId)
 Check ($sample.ProcessId -eq $PID) 'Native PID differs'
 Check ($sample.StartTime -ceq $self.StartTime.ToUniversalTime().ToString('o')) 'Creation time differs from .NET identity'
 Check ($sample.CpuMs -ge 0 -and $sample.CpuMs -le $self.TotalProcessorTime.TotalMilliseconds) 'Invalid CPU time'
 Check ($null -eq [Bnqq.TelemetryV3.ProcessTelemetry]::Read($PID,'bnqq-wrong-image',(Get-BnqqOwner),[uint32]$self.SessionId)) 'Image race admitted'
 MustThrow {[Bnqq.TelemetryV3.ProcessTelemetry]::Read($PID,$self.ProcessName,'S-1-0-0',[uint32]$self.SessionId)}
 MustThrow {[Bnqq.TelemetryV3.ProcessTelemetry]::Read($PID,$self.ProcessName,(Get-BnqqOwner),[uint32]($self.SessionId+1))}
 MustThrow {[Bnqq.TelemetryV3.ProcessTelemetry]::Read(0,$self.ProcessName,(Get-BnqqOwner),[uint32]$self.SessionId)}
 Check ($null -eq [Bnqq.TelemetryV3.ProcessTelemetry]::Read([int]::MaxValue,$self.ProcessName,(Get-BnqqOwner),[uint32]$self.SessionId)) 'Exited PID invented'
 $priority=[Bnqq.TelemetryV3.ProcessTelemetry]::ReadPriority($PID,$sample.Name,$sample.StartTime,(Get-BnqqOwner),[uint32]$self.SessionId)
 Check ($priority.Priority -ceq $self.PriorityClass.ToString() -and $priority.StartTime -ceq $sample.StartTime) 'Native priority/identity differs from .NET'
 $discovered=[Bnqq.TelemetryV3.ProcessTelemetry]::ReadPriority($PID,'','',(Get-BnqqOwner),[uint32]$self.SessionId)
 Check ($discovered.Name -ceq $priority.Name -and $discovered.Priority -ceq $priority.Priority) 'Native priority discovery differs'
 Check ($null -eq [Bnqq.TelemetryV3.ProcessTelemetry]::ReadPriority($PID,$sample.Name,'wrong-start',(Get-BnqqOwner),[uint32]$self.SessionId)) 'Priority query accepted reused PID identity'
 Check ($null -eq [Bnqq.TelemetryV3.ProcessTelemetry]::ReadPriority($PID,'wrong-name',$sample.StartTime,(Get-BnqqOwner),[uint32]$self.SessionId)) 'Priority query accepted different image'
 MustThrow {[Bnqq.TelemetryV3.ProcessTelemetry]::ReadPriority($PID,$sample.Name,$sample.StartTime,'S-1-0-0',[uint32]$self.SessionId)}
 MustThrow {[Bnqq.TelemetryV3.ProcessTelemetry]::ReadPriority($PID,$sample.Name,$sample.StartTime,(Get-BnqqOwner),[uint32]($self.SessionId+1))}
 MustThrow {[Bnqq.TelemetryV3.ProcessTelemetry]::ReadPriority($PID,$sample.Name,'',(Get-BnqqOwner),[uint32]$self.SessionId)}
 Check ($null -eq [Bnqq.TelemetryV3.ProcessTelemetry]::ReadPriority([int]::MaxValue,'','',(Get-BnqqOwner),[uint32]$self.SessionId)) 'Priority query invented exited PID'
}finally{$self.Dispose()}
Add-Type @'
public sealed class BnqqSampleFixtureProcess : System.IDisposable {
 public int Id; public string ProcessName="msedge"; public bool Disposed;
 public void Dispose(){Disposed=true;}
}
'@
$script:enumerations=0;$script:reads=0;$script:logs=0;$script:fixtures=@();$script:observedNames=@()
function Get-Process {param([string[]]$Name,$ErrorAction);$script:enumerations++;$script:observedNames=$Name;return $script:fixtures}
function Get-BnqqNativeFocusSample {
 param([int]$ProcessId,[string]$Name)
 $script:reads++
 if($ProcessId -eq 99){throw 'Fixture access denied'}
 if($ProcessId -eq 98){return $null}
 [pscustomobject]@{ProcessId=$ProcessId;Name=$Name;StartTime='identity-'+$ProcessId;CpuMs=123}
}
function Write-BnqqNightLog {param($Kind,$Message);$script:logs++}
$script:fixtures=@(1..3|ForEach-Object {$p=New-Object BnqqSampleFixtureProcess;$p.Id=$_;$p})
$rows=@(Get-BnqqFocusSamples @('msedge','MSEDGE','chrome','firefox','OneDrive'))
Check ($script:enumerations -eq 1 -and $script:observedNames.Count -eq 4) 'Apps were not batched/deduplicated'
Check ($rows.Count -eq 3 -and $script:reads -eq 3) 'Sample identities/counters lost'
Check (@($script:fixtures|Where-Object {-not $_.Disposed}).Count -eq 0) 'Process wrappers leaked'
$before=$script:enumerations
Check (@(Get-BnqqFocusSamples @()).Count -eq 0) 'Empty selection generated samples'
Check ($before -eq $script:enumerations) 'Empty selection enumerated the host'
MustThrow {Get-BnqqFocusSamples @('*')}
Check ($before -eq $script:enumerations) 'Wildcard passed validation'
$script:fixtures=@(98,99,7|ForEach-Object {$p=New-Object BnqqSampleFixtureProcess;$p.Id=$_;$p})
$rows=@(Get-BnqqFocusSamples @('msedge'))
Check ($rows.Count -eq 1 -and $rows[0].ProcessId -eq 7) 'Exit/access denial broke remaining samples'
Check ($script:logs -eq 1) 'Access denial not recorded'
Check (@($script:fixtures|Where-Object {-not $_.Disposed}).Count -eq 0) 'Failure cleanup leaked wrappers'
[void](Get-BnqqFocusSamples @('msedge'))
Check ($script:logs -eq 1) 'Repeated error flooded log'
$script:fixtures=@(1..129|ForEach-Object {$p=New-Object BnqqSampleFixtureProcess;$p.Id=$_;$p})
$before=$script:reads
MustThrow {Get-BnqqFocusSamples @('msedge')}
Check ($script:reads -eq $before) 'Over-cap snapshot read target handles'
Check (@($script:fixtures|Where-Object {-not $_.Disposed}).Count -eq 0) 'Over-cap cleanup leaked wrappers'
"PASS: process sampling $checks checks; read-only native identity/scope, batching, churn and cleanup"
