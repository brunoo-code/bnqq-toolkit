#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\SyntheticBench.ps1')
$script:names=@('explorer','powershell');$script:disposed=0;$script:focus=$false
function Get-Process {
 param($ErrorAction)
 foreach($name in $script:names){$p=[pscustomobject]@{ProcessName=$name};$p|Add-Member ScriptMethod Dispose {$script:disposed++};$p}
}
function Assert-BnqqNoDynamicFocus {if($script:focus){throw 'Focus active fixture'}}
function MustThrow([scriptblock]$c){$hit=$false;try{& $c}catch{$hit=$true};if(-not $hit){throw 'Expected process guard refusal'}}
Assert-BnqqSyntheticNoGame
if($script:disposed -ne 2){throw 'Process objects not disposed'}
foreach($name in @('cs2','VALORANT-Win64-Shipping','PresentMon-2.4.0-x64')){
 $script:names=@($name);$before=$script:disposed;MustThrow {Assert-BnqqSyntheticNoGame}
 if($script:disposed -ne $before+1){throw 'Blocked process object leaked'}
}
$script:names=@('explorer');$script:focus=$true;MustThrow {Assert-BnqqSyntheticNoGame}
'PASS: synthetic process guard, versioned PresentMon, focus refusal and disposal; no native load'
