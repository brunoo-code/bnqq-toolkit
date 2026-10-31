$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
foreach($n in @('Core','NicPolicy')){. (Join-Path $script:BnqqRoot ('lib\'+$n+'.ps1'))}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-nic-'+[guid]::NewGuid().ToString('N'))
$script:BnqqDataRoot=$temp;$script:writes=0;$script:qa=$true;$script:admin=$true;$script:partial=$false;$script:healthy=$true;$script:capable=$true
$script:adapter=[pscustomobject]@{Name='Ethernet [lab]';InterfaceGuid='11111111-1111-1111-1111-111111111111';PnPDeviceID='PCI\NIC-FIXTURE';DriverVersion='1.0';HardwareInterface=$true;Status='Up'}
$script:state=@{};foreach($key in (Get-BnqqNicKeywords)){$script:state[$key]=@('0')}
function Check($ok,$message){if(-not $ok){throw $message}}
function MustThrow([scriptblock]$Code){$hit=$false;try{& $Code|Out-Null}catch{$hit=$true};Check $hit 'Expected refusal'}
function Get-NetAdapter {param([switch]$Physical,$ErrorAction);return @($script:adapter,[pscustomobject]@{Name='Virtual';HardwareInterface=$false;Status='Up'})}
function Get-NetAdapterAdvancedProperty {
 param($Name,[switch]$AllProperties,$ErrorAction)
 Check ($Name -ceq [WildcardPattern]::Escape($script:adapter.Name)) 'Adapter name wildcard was not escaped'
 foreach($key in $script:state.Keys){[pscustomobject]@{Name=$script:adapter.Name;RegistryKeyword=$key;RegistryValue=@($script:state[$key]);ValidRegistryValues=$(if($script:capable){@('0','1','2','3')}else{@('0')})}}
}
function Set-NetAdapterAdvancedProperty {
 param($InputObject,$RegistryValue,[switch]$NoRestart,[switch]$Confirm,$ErrorAction)
 Check ($NoRestart -and -not $Confirm) 'Adapter restart must never occur implicitly'
 $disk=@(Get-ChildItem (Join-Path $temp 'nic-journals') -Filter '*.json'|ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json}|Where-Object Status -ne 'Restored')
 Check ($disk.Count -eq 1 -and @($disk[0].Entries|Where-Object Keyword -eq $InputObject.RegistryKeyword).Count -eq 1) 'Missing write-ahead property backup'
 $script:writes++;$script:state[$InputObject.RegistryKeyword]=@($RegistryValue)
 if($script:partial){$script:partial=$false;throw 'Failure after native property write'}
}
function Test-BnqqAdmin {return $script:admin}
function Assert-BnqqHeavyQa {if(-not $script:qa){throw 'QA refusal'}}
function Assert-BnqqMemoryHeadroom {}
function Assert-BnqqPhaseHealth {param($Since);if(-not $script:healthy){throw 'WHEA fixture'}}
function Write-BnqqNightLog {param($Stage,$Message)}
try {
 Check (@(Get-BnqqPhysicalAdapters).Count -eq 1) 'Virtual interface admitted'
 MustThrow {Resolve-BnqqNic -Name '*'}
 $p=Get-BnqqNicPlan;Check ($p.Entries.Count -eq 3 -and $script:writes -eq 0) 'Plan failed/no-write broken'
 $script:capable=$false;$unsupported=Get-BnqqNicPlan;Check ($unsupported.Status -eq 'Unsupported' -and $unsupported.Entries.Count -eq 0) 'Unsupported values became generic tweaks';$script:capable=$true
 $script:qa=$false;MustThrow {Invoke-BnqqNicPolicy -Action stage};$script:qa=$true
 $script:admin=$false;MustThrow {Invoke-BnqqNicPolicy -Action stage};$script:admin=$true
 Check ($script:writes -eq 0) 'Guard changed a NIC property'
 $r=Invoke-BnqqNicPolicy -Action stage
 Check ($r.Status -eq 'Staged' -and $r.RequiresAdapterRestart -and $r.RuntimeActivation -eq 'NotAssumed') 'Configuration was advertised as runtime activation'
 Check (@($script:state.Values|Where-Object {$_[0] -ne '3'}).Count -eq 0) 'Configured values missing'
 $script:qa=$false;$script:adapter.Name='Renamed [lab]';Invoke-BnqqNicPolicy -Action restore -File $r.Journal|Out-Null;$script:qa=$true
 Check (@($script:state.Values|Where-Object {$_[0] -ne '0'}).Count -eq 0) 'Original properties not restored'
 $count=$script:writes;Restore-BnqqNicPolicy $r.Journal|Out-Null;Check ($script:writes -eq $count) 'Recovery not idempotent'
 $script:partial=$true;MustThrow {Invoke-BnqqNicPolicy -Action stage}
 Check (@($script:state.Values|Where-Object {$_[0] -ne '0'}).Count -eq 0) 'Partial configuration not recovered'
 $script:healthy=$false;MustThrow {Invoke-BnqqNicPolicy -Action stage};$script:healthy=$true
 Check (@($script:state.Values|Where-Object {$_[0] -ne '0'}).Count -eq 0) 'WHEA rollback failed'
 $r=Invoke-BnqqNicPolicy -Action stage;$key=(Get-BnqqNicKeywords)[0];$script:state[$key]=@('1');$count=$script:writes
 MustThrow {Restore-BnqqNicPolicy $r.Journal}
 Check ($script:state[$key][0] -eq '1') 'External property overwritten'
 $script:state[$key]=@('3');$script:adapter.DriverVersion='2.0';$count=$script:writes;MustThrow {Restore-BnqqNicPolicy $r.Journal};Check ($script:writes -eq $count) 'Different driver modified';$script:adapter.DriverVersion='1.0'
 Restore-BnqqNicPolicy $r.Journal|Out-Null
 $j=Get-Content $r.Journal -Raw|ConvertFrom-Json;$j.Entries[0].Keyword='NetworkAddress';Write-BnqqAtomicJson $j $r.Journal
 MustThrow {Restore-BnqqNicPolicy $r.Journal}
 foreach($key in @($script:state.Keys)){$script:state[$key]=@('3')}
 Check ((Get-BnqqNicPlan).Status -eq 'AlreadyConfigured') 'No-op was not detected'
 'PASS: physical adapter identity, escaped names, driver capabilities, NoRestart setter, write-ahead, permission/QA, partial failure, WHEA, external conflicts and rollback'
}finally{
 $full=[IO.Path]::GetFullPath($temp)
 if(-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
 if([IO.Directory]::Exists($full)){[IO.Directory]::Delete($full,$true)}
}
