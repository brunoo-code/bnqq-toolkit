#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$r=& $exe -NoProfile -File (Join-Path $root 'bnqq.ps1') drivers -DryRun
if($LASTEXITCODE -ne 0 -or (($r -join "`n")|ConvertFrom-Json).Status -ne 'Preview'){throw 'Drivers preview CLI failed'}
$r=& $exe -NoProfile -File (Join-Path $root 'bnqq.ps1') dpc
if($LASTEXITCODE -ne 0){throw 'DPC contract CLI failed'}
$m=($r -join "`n")|ConvertFrom-Json
if($m.Schema -ne 'BNQQ.DpcCsv.1' -or $m.Columns.Count -ne 5 -or $m.Metadata.Clock -ne 'QPC'){throw 'Wrong DPC contract'}
$r=& $exe -NoProfile -File (Join-Path $root 'bnqq.ps1') dpc -DpcCsv 'missing.csv' -DpcMetadata 'missing.json' -DryRun
if($LASTEXITCODE -ne 0 -or (($r -join "`n")|ConvertFrom-Json).Schema -ne 'BNQQ.DpcCsv.1'){throw 'DryRun opened input files'}
'PASS: drivers preview, DPC contract and DryRun without input access or capture'
