#Requires -Version 5.1
# Minimal real lifecycle on a disposable CI runner, NEVER on the developer host.
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true'){'SKIP: native worker lifecycle is CI-only; no local load started';return}
$root=Split-Path -Parent $PSScriptRoot
Add-Type -Path (Join-Path $root 'lib\SyntheticLoad.cs')
$load=New-Object Bnqq.SyntheticLoad
try {
 $load.Start(1,1,10,100,1)
 $clock=[Diagnostics.Stopwatch]::StartNew()
 while($load.Running -and $clock.Elapsed.TotalSeconds -lt 5){Start-Sleep -Milliseconds 20}
 $load.Stop()
 if($load.Running -or $load.Failed -or $load.Passes -lt 1){throw 'Native deadline/verified progress failed'}
}finally{$load.Dispose()}
$load=New-Object Bnqq.SyntheticLoad
try{
 $load.Start(1,120,10,100,1)
 Start-Sleep -Milliseconds 30
 $load.Stop()
 if($load.Running -or $load.Failed){throw 'Cooperative native stop failed'}
}finally{$load.Dispose()}
'PASS: CI-only native one-thread 10% duty lifecycle, self-deadline, verified progress and cooperative stop'
