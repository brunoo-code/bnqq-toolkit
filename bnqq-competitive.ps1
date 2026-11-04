#Requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('','cs2.exe','VALORANT-Win64-Shipping.exe')][string]$FrameProcess='',[string[]]$KeepApps=@('Discord','Spotify'),[ValidateRange(1,240)][int]$SessionMinutes=240,[switch]$DryRun,[switch]$StopSession,[switch]$Diagnostics)
$ErrorActionPreference='Stop';$script:BnqqRoot=$PSScriptRoot
foreach($n in @('Core','Governance','Readiness','RuntimeLatency','CpuSession','ProcessSampling','BackgroundBudget','Maintenance','NetworkSession','FocusSession','CompetitiveStart','CompetitiveConsole')){. (Join-Path $script:BnqqRoot ('lib\'+$n+'.ps1'))}
if($Diagnostics){
 $Error.Clear();$cert=Get-BnqqLatestHeavyQa -WorkloadOnly;$readerError=if($Error.Count){$Error[0].Exception.Message}else{$null}
 $fp=$null;$fpError=$null;try{$fp=Get-BnqqConfigurationFingerprint -WorkloadOnly}catch{$fpError=$_.Exception.Message}
 [pscustomobject]@{Schema='BNQQ.CompetitiveDiagnostics.1';PowerShell=$PSVersionTable.PSVersion.ToString();Is64Bit=[Environment]::Is64BitProcess;HashCommandAvailable=[bool](Get-Command Get-FileHash -ErrorAction SilentlyContinue);Culture=[Globalization.CultureInfo]::CurrentCulture.Name;DataRoot=(Get-BnqqDataRoot);CertificateFound=($null -ne $cert);CertificatePassed=$cert.Passed;ReaderError=$readerError;Fingerprint=$fp;FingerprintError=$fpError}|ConvertTo-Json;return
}
if($StopSession){if($DryRun){[pscustomobject]@{Status='Preview';WouldStop=$true}|ConvertTo-Json}else{Invoke-BnqqCompetitiveStart -Action stop|Format-List};return}
if($DryRun){Show-BnqqCompetitiveConsole -Game $FrameProcess -KeepApps $KeepApps -MaxMinutes $SessionMinutes -DryRun|ConvertTo-Json -Depth 10}
else{Show-BnqqCompetitiveConsole -Game $FrameProcess -KeepApps $KeepApps -MaxMinutes $SessionMinutes}
