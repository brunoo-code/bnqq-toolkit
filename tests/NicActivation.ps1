$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($n in @('Core','NicPolicy')){. (Join-Path $script:BnqqRoot ('lib\'+$n+'.ps1'))}
if(-not ('BnqqChecksumTestDirection' -as [type])){Add-Type 'public enum BnqqChecksumTestDirection { Disabled=0, TxEnabled=1, RxEnabled=2, RxTxEnabled=3 }'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-nic-active-'+[guid]::NewGuid().ToString('N'))
$script:BnqqDataRoot=$temp;$script:checks=0
function Check($v,$m){if(-not $v){throw $m};$script:checks++}
function MustThrow([scriptblock]$c){$hit=$false;try{& $c|Out-Null}catch{$hit=$true};Check $hit 'Expected refusal'}
function Reset {
 if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
 $script:a=[pscustomobject]@{Name='Eth[qa]';InterfaceGuid='23ea78b2-611e-44b5-a72e-d51f39d0f719';PnPDeviceID='fixture';DriverVersion='1';Status='Up';InterfaceIndex=3}
 $script:reg=@{};$script:runtime=@{};foreach($k in (Get-BnqqNicKeywords)){$script:reg[$k]='0';$script:runtime[$k]='0'}
 $script:resets=0;$script:admin=$true;$script:qa=$true;$script:healthy=$true;$script:failReset=$false;$script:mirror=$false;$script:globalOffload='Enabled';$script:clock=[pscustomobject]@{Elapsed=[pscustomobject]@{TotalSeconds=0}}
}
function Get-BnqqPhysicalAdapters {return @($script:a)}
function Get-BnqqNicProperty {param($Adapter,$Keyword);[pscustomobject]@{RegistryKeyword=$Keyword;RegistryValue=@($script:reg[$Keyword]);ValidRegistryValues=@('0','1','2','3')}}
function Set-BnqqNicProperty {param($Identity,$Keyword,$Expected,$Value);Check ($script:reg[$Keyword] -eq $Expected[0]) 'Foreign property overwritten';$script:reg[$Keyword]=$Value[0]}
function Test-BnqqAdmin {return $script:admin}
function Assert-BnqqHeavyQa {if(-not $script:qa){throw 'QA refused'}}
function Assert-BnqqMemoryHeadroom {}
function Assert-BnqqPhaseHealth {param($Since);if(-not $script:healthy){throw 'New WHEA'}}
function Write-BnqqNightLog {param($Stage,$Message)}
function Get-NetAdapterChecksumOffload {
 param($Name,$ErrorAction)
 $s=if($script:mirror){$script:reg}else{$script:runtime}
 [pscustomobject]@{IpIPv4Enabled=[BnqqChecksumTestDirection][int]$s['*IPChecksumOffloadIPv4'];UdpIPv4Enabled=[BnqqChecksumTestDirection][int]$s['*UDPChecksumOffloadIPv4'];UdpIPv6Enabled=[BnqqChecksumTestDirection][int]$s['*UDPChecksumOffloadIPv6']}
}
function Get-NetRoute {param($InterfaceIndex,$ErrorAction);[pscustomobject]@{DestinationPrefix='0.0.0.0/0';NextHop='192.0.2.1'}}
function Get-NetOffloadGlobalSetting {param($ErrorAction);[pscustomobject]@{TaskOffload=$script:globalOffload}}
function Restart-NetAdapter {
 param($Name,$Confirm,$ErrorAction)
 Check ($Name -ceq [WildcardPattern]::Escape($script:a.Name)) 'Wildcard device restart';Check (-not $Confirm) 'Unexpected prompt'
 $script:resets++;foreach($k in (Get-BnqqNicKeywords)){$script:runtime[$k]=$script:reg[$k]}
 if($script:failReset){$script:failReset=$false;throw 'Reset failed after driver reloaded'}
}
function New-BnqqNicActivationClock {$script:clock.Elapsed.TotalSeconds=0;return $script:clock}
function Start-Sleep {param($Milliseconds);$script:clock.Elapsed.TotalSeconds+=10}
try{
 Reset;$staged=Invoke-BnqqNicPolicy -Action stage;Check ($script:resets -eq 0 -and $script:runtime['*UDPChecksumOffloadIPv4'] -eq '0') 'Stage falsely activated driver'
 $r=Invoke-BnqqNicActivation $staged.Journal;Check ($r.Status -eq 'Activated' -and $r.Restarted -and $script:resets -eq 1) 'Activation not verified'
 Check (-not $r.RequiresAdapterRestart) 'Still pending after reset';$r=Invoke-BnqqNicActivation $staged.Journal;Check ($script:resets -eq 1 -and -not $r.Restarted) 'Idempotent activation reset again'
 $r=Invoke-BnqqNicActivation $staged.Journal -Restore;Check ($r.Status -eq 'RestoredActive' -and $script:resets -eq 2 -and $script:runtime['*UDPChecksumOffloadIPv4'] -eq '0') 'Original runtime not restored'
 Reset;$s=Invoke-BnqqNicPolicy -Action stage;$script:mirror=$true;$r=Invoke-BnqqNicActivation $s.Journal;Check ($script:resets -eq 1) 'CIM registry mirror skipped required first reset'
 Reset;$s=Invoke-BnqqNicPolicy -Action stage;$script:failReset=$true;MustThrow {Invoke-BnqqNicActivation $s.Journal};Check ($script:resets -eq 2 -and $script:runtime['*UDPChecksumOffloadIPv4'] -eq '0') 'Partial reset not rolled back to original runtime'
 Reset;$s=Invoke-BnqqNicPolicy -Action stage;$script:healthy=$false;MustThrow {Invoke-BnqqNicActivation $s.Journal};Check ($script:runtime['*UDPChecksumOffloadIPv4'] -eq '0') 'New WHEA did not roll back runtime'
 Reset;$s=Invoke-BnqqNicPolicy -Action stage;$script:reg['*UDPChecksumOffloadIPv4']='1';MustThrow {Invoke-BnqqNicActivation $s.Journal};Check ($script:resets -eq 0) 'Foreign setting restarted'
 Reset;$s=Invoke-BnqqNicPolicy -Action stage;$script:a.DriverVersion='2';MustThrow {Invoke-BnqqNicActivation $s.Journal};Check ($script:resets -eq 0) 'Different driver restarted'
 Reset;$s=Invoke-BnqqNicPolicy -Action stage;$script:a.Status='Disabled';MustThrow {Invoke-BnqqNicActivation $s.Journal};Check ($script:resets -eq 0) 'Disabled adapter enabled'
 Reset;$s=Invoke-BnqqNicPolicy -Action stage;$script:qa=$false;MustThrow {Invoke-BnqqNicActivation $s.Journal};Check ($script:resets -eq 0) 'QA gate changed runtime'
 Reset;$s=Invoke-BnqqNicPolicy -Action stage;$script:globalOffload='Disabled';MustThrow {Invoke-BnqqNicActivation $s.Journal};Check ($script:resets -eq 0) 'Globally disabled offload falsely activated'
 $script:qa=$true;$script:admin=$false;MustThrow {Invoke-BnqqNicActivation $s.Journal};Check ($script:resets -eq 0) 'Nonadmin activation started'
 Reset;$s=Invoke-BnqqNicPolicy -Action stage;$j=Read-BnqqNicJournal $s.Journal;$j.Owner='foreign';Write-BnqqAtomicJson $j $s.Journal;MustThrow {Invoke-BnqqNicActivation $s.Journal};Check ($script:resets -eq 0) 'Foreign backup reset hardware'
 ('PASS: '+$script:checks+' NIC activation checks; staged vs runtime, forced first reset, idempotence, original-state reset, partial failure, WHEA and driver/owner/setting conflicts')
}finally{if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}}
