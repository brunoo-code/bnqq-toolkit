#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$lines=& $exe -NoProfile -File (Join-Path $root 'bnqq.ps1') synthetic -SyntheticAction run -SyntheticSeconds 3 -SyntheticThreads 1 -DryRun
if($LASTEXITCODE -ne 0){throw 'Synthetic CLI preview failed'}
$p=($lines -join "`n")|ConvertFrom-Json
if($p.Schema -ne 'BNQQ.SyntheticPlan.1' -or $p.Threads -ne 1 -or $p.Seconds -ne 3 -or $p.PrefireEquivalent){throw 'Synthetic CLI did not preserve dry-run/limits'}
'PASS: synthetic CLI explicit run + DryRun produces only a plan'
