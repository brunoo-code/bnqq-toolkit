[CmdletBinding()]
param([Parameter(Mandatory)][string]$Scenario,[Parameter(Mandatory)][string]$SettingsHash,[Parameter(Mandatory)][string]$ExperimentId,[Parameter(Mandatory)][ValidateSet('baseline','candidate')][string]$Variant,[string]$SwapChain)
$ErrorActionPreference='Stop'
Write-Host 'Tres rodadas da variante informada. Para conclusao, intercale A/B/BA em sessoes individuais com framebench.'
for($i=1;$i -le 3;$i++){
    & (Join-Path (Split-Path -Parent $PSScriptRoot) 'bnqq.ps1') framebench -Scenario $Scenario -SettingsHash $SettingsHash -ExperimentId $ExperimentId -Variant $Variant -SwapChain $SwapChain
    if($LASTEXITCODE -ne 0){throw 'Captura falhou; nao produzir veredito parcial'}
}
