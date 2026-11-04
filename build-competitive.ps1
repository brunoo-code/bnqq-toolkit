[CmdletBinding()]
param([string]$OutputPath,[ValidatePattern('^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$')][string]$Version='2.6.0',[switch]$KeepBuild)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'build.ps1') -Mode Competitive -Version $Version -OutputPath $OutputPath -KeepBuild:$KeepBuild
