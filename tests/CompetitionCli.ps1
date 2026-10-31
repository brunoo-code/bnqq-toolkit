#Requires -Version 5.1
# Read-only native capability preview; no game, load worker or policy starts.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$lines=& $exe -NoProfile -File (Join-Path $root 'bnqq.ps1') compete -CompetitionAction run -DryRun
if($LASTEXITCODE -ne 0){throw 'Competition CLI preview failed'}
$p=($lines -join "`n")|ConvertFrom-Json
if($p.Schema -ne 'BNQQ.CompetitionPlan.1' -or $p.Focus.Policy -ne 'Priority' -or $p.Focus.Apps.Count -ne 4 -or $p.ChangesGameConfig -or $p.ChangesPowerClock -or $p.ChangesGpuDriver -or $p.Upload.Apps.Count){throw 'Competition CLI DryRun contract failed'}
'PASS: competition native hardware/readiness preview; no implicit network, driver, game or power changes'
