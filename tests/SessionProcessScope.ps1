#Requires -Version 5.1
# Exercise production process adapter with a disposable fake, never host processes.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\GameSession.ps1')
. (Join-Path $root 'lib\FocusSession.ps1')
$script:allowed=$true;$script:checks=0
$script:fake=[pscustomobject]@{Id=20;ProcessName='msedge';StartTime=[datetime]'2026-01-01T12:00:00Z';Handle=[IntPtr]7;PriorityClass='Normal';Disposals=0}
$script:fake|Add-Member ScriptMethod Dispose {$this.Disposals++}
function Check($v,$t){if(-not $v){throw $t};$script:checks++}
function MustThrow([scriptblock]$c){$hit=$false;try{& $c|Out-Null}catch{$hit=$true};Check $hit 'Expected session refusal'}
function Get-Process {param($Id,$ErrorAction);if($Id -eq 20){return $script:fake}}
function Assert-BnqqCpuProcessScope {param($Process,$Handle);Check ($Handle -eq [IntPtr]7) 'Wrong handle';if(-not $script:allowed){throw 'Foreign SID/session fixture'}}
$before=Get-BnqqSessionProcess 20
Check ($before.Priority -eq 'Normal') 'Native-adapter snapshot failed'
$script:allowed=$false;MustThrow {Get-BnqqSessionProcess 20};MustThrow {Set-BnqqSessionPriority 20 BelowNormal $before}
Check ($script:fake.PriorityClass -eq 'Normal') 'Foreign process changed'
$script:allowed=$true;Set-BnqqSessionPriority 20 BelowNormal $before
Check ($script:fake.PriorityClass -eq 'BelowNormal') 'Priority did not apply'
MustThrow {Set-BnqqSessionPriority 20 Normal $before}
$live=Get-BnqqSessionProcess 20;Set-BnqqSessionPriority 20 Normal $live
Check ($script:fake.PriorityClass -eq 'Normal' -and $script:fake.Disposals -eq 7) 'Restore/disposal failed'
$focusIdentity=Get-BnqqFocusIdentity 20
Check ($focusIdentity.StartTime -eq $before.StartTime) 'Focus identity adapter failed'
$script:allowed=$false;MustThrow {Get-BnqqFocusIdentity 20}
('PASS: session process adapter '+$script:checks+' checks; identity, foreign scope, priority race and disposal')
