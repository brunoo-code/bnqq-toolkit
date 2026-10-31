# Read only; no assumption that a WHEA event identifies a specific CO value or failed part.
$ErrorActionPreference='Stop'
$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $script:BnqqRoot 'lib\Core.ps1')
. (Join-Path $script:BnqqRoot 'lib\Governance.ps1')
Get-BnqqWheaEvents | Select-Object Error,@{n='Events';e={@($_.Events|Select-Object TimeCreated,Id,ProviderName,Message)}} | ConvertTo-Json -Depth 5
