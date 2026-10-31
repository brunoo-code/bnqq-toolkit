#Requires -Version 5.1
[CmdletBinding()]
param([switch]$PinPhysical,[switch]$AboveNormal,[switch]$ObserveWmi,[switch]$Once,[switch]$DeepFreeze,[switch]$RespectBattery,[int]$IntervalSeconds=2)
$ErrorActionPreference='Stop'
if($DeepFreeze -or $RespectBattery){throw 'Argumentos legados retirados. Nao iniciar com tarefas antigas; reveja docs/MIGRATION.md.'}
& (Join-Path $PSScriptRoot 'bnqq.ps1') watch -WatcherAction run -PinPhysical:$PinPhysical -AboveNormal:$AboveNormal -ObserveWmi:$ObserveWmi -Once:$Once
