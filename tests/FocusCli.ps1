#Requires -Version 5.1
# Read-only CLI previews: no game, WMI, driver or QA worker started.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$psExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$lines=& $psExe -NoProfile -File (Join-Path $root 'bnqq.ps1') focus -FocusAction plan -FocusPolicy Priority -SessionApps msedge -SessionMinutes 1 -DryRun
if($LASTEXITCODE -ne 0){throw 'Priority preview CLI binding failed'}
$plan=($lines -join "`n")|ConvertFrom-Json
if($plan.Status -ne 'Preview' -or $plan.Policy -ne 'Priority' -or @($plan.Apps).Count -ne 1 -or $plan.Apps[0] -ne 'msedge' -or @($plan.Cpu.Operations).Count -or @($plan.Maintenance.Operations).Count){throw 'Priority CLI preview contract failed'}
$lines=& $psExe -NoProfile -File (Join-Path $root 'bnqq.ps1') focus -DryRun
if($LASTEXITCODE -ne 0){throw 'Default focus CLI parameters missing'}
$plan=($lines -join "`n")|ConvertFrom-Json
if($plan.Status -ne 'Preview' -or $plan.Policy -ne 'CpuSets'){throw 'Default focus policy changed unexpectedly'}
'PASS: explicit priority preview and default focus CLI, no runtime session'
