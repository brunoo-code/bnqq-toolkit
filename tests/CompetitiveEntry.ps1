#Requires -Version 5.1
# Actual dedicated entrypoint, previews only. No game or controller is started.
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot;$exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$r=& $exe -NoProfile -File (Join-Path $root 'bnqq-competitive.ps1') -DryRun
if($LASTEXITCODE -ne 0){throw 'Dedicated entrypoint preview failed'}
$j=($r -join "`n")|ConvertFrom-Json
if($j.Status -ne 'SelectGame' -and $j.Schema -ne 'BNQQ.CompetitiveStart.1'){throw 'Dedicated entrypoint opened the full optimizer or returned invalid data'}
$r=& $exe -NoProfile -File (Join-Path $root 'bnqq-competitive.ps1') -StopSession -DryRun
if($LASTEXITCODE -ne 0 -or -not (($r -join "`n")|ConvertFrom-Json).WouldStop){throw 'Stop preview failed'}
'PASS: dedicated competitive entrypoint and stop preview without launch, stress or mutation'
