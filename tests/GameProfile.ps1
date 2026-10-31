$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\GameProfile.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-gameprofile-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$script:BnqqDataRoot=Join-Path $temp 'data'
function Get-Process {param($Name,$ErrorAction);return $null}
function Check($ok,$message){if(-not $ok){throw $message}}
function MustThrow([scriptblock]$Code){$hit=$false;try{& $Code|Out-Null}catch{$hit=$true};Check $hit 'Expected refusal'}
try{
 $path=Join-Path $temp 'cs2_video.txt'
 $original=[Text.Encoding]::UTF8.GetBytes("`"video.cfg`"`r`n{`r`n`t`"setting.msaa_samples`" `"8`"`r`n`t`"setting.r_low_latency`" `"2`"`r`n}// ação")
 [IO.File]::WriteAllBytes($path,$original)
 $hash=Get-BnqqByteHash $original
 Invoke-BnqqGameProfile $temp plan | Out-Null
 Check ((Get-BnqqByteHash ([IO.File]::ReadAllBytes($path))) -ceq $hash) 'Preview changed file'
 $applied=Invoke-BnqqGameProfile $temp apply
 Check ($applied.Status -eq 'Applied') 'Apply failed'
 Check ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($path)).Contains('"setting.msaa_samples" "2"')) 'MSAA not changed'
 Invoke-BnqqGameProfile $temp restore -BackupFile $applied.Backup | Out-Null
 Check ((Get-BnqqByteHash ([IO.File]::ReadAllBytes($path))) -ceq $hash) 'Not byte-exact restore'
 Invoke-BnqqGameProfile $temp restore -BackupFile $applied.Backup | Out-Null
 $second=Invoke-BnqqGameProfile $temp apply
 Check ($second.Backup -ne $applied.Backup) 'Backup overwritten'
 Add-Content $path '// external edit'
 MustThrow {Invoke-BnqqGameProfile $temp restore -BackupFile $second.Backup}
 MustThrow {Convert-BnqqMsaaProfile ([Text.Encoding]::ASCII.GetBytes('unknown'))}
 MustThrow {Convert-BnqqMsaaProfile ([Text.Encoding]::ASCII.GetBytes('"setting.msaa_samples" "8" "setting.msaa_samples" "8"'))}
 [IO.File]::WriteAllBytes($path,$original)
 function Get-Process {param($Name,$ErrorAction);return [pscustomobject]@{Name='cs2'}}
 MustThrow {Invoke-BnqqGameProfile $temp apply}
 Check ((Get-BnqqByteHash ([IO.File]::ReadAllBytes($path))) -ceq $hash) 'Open-game refusal wrote file'
 'PASS: game profile preview, apply, byte-exact/idempotent rollback, immutable backups, schema, conflict and open-game refusal'
}finally{if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}}
