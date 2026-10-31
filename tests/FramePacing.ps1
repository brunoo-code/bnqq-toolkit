$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\GameProfile.ps1')
. (Join-Path $root 'lib\FramePacing.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-gameprofile-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$script:BnqqDataRoot=Join-Path $temp 'data'
function Get-Process {param($Name,$ErrorAction);return $null}
function Check($ok,$message){if(-not $ok){throw $message}}
function MustThrow([scriptblock]$Code){$hit=$false;try{& $Code|Out-Null}catch{$hit=$true};Check $hit 'Expected refusal'}
try{
 Check (@(Find-BnqqCs2Configs -SteamRoot $temp).Count -eq 0) 'Missing Steam userdata must not guess'
 $fixture=Join-Path $temp 'userdata\123\730\local\cfg'
 [void][IO.Directory]::CreateDirectory($fixture)
 [IO.File]::WriteAllText((Join-Path $fixture 'cs2_video.txt'),'fixture')
 Check (@(Find-BnqqCs2Configs -SteamRoot $temp).Count -eq 1) 'Steam profile discovery failed'
 $fixture2=Join-Path $temp 'userdata\456\730\local\cfg'
 [void][IO.Directory]::CreateDirectory($fixture2)
 [IO.File]::WriteAllText((Join-Path $fixture2 'cs2_video.txt'),'fixture')
 Check (@(Find-BnqqCs2Configs -SteamRoot $temp).Count -eq 2) 'Multiple profiles must remain distinct'
 $path=Join-Path $temp 'cs2_machine_convars.vcfg'
 $original=[Text.Encoding]::UTF8.GetBytes("`"video.cfg`"`r`n{`r`n`t`"fps_max`" `"0`"`r`n`t`"fps_max_ui`$2`" `"0`"`r`n`t`"setting.r_low_latency`" `"2`"`r`n}// ação")
 [IO.File]::WriteAllBytes($path,$original)
 $preserved=[Text.Encoding]::UTF8.GetString((Convert-BnqqFrameCaps $original))
 Check ($preserved.Contains('"fps_max" "0"')) 'Default must preserve gameplay cap'
 $limited=[Text.Encoding]::UTF8.GetString((Convert-BnqqFrameCaps $original 240 60))
 Check ($limited.Contains('"fps_max" "240"') -and $limited.Contains('"fps_max_ui$2" "60"')) 'Explicit game/menu caps independent'
 MustThrow {Convert-BnqqFrameCaps $original 59 120}
 MustThrow {Convert-BnqqFrameCaps $original -2 120}
 MustThrow {Convert-BnqqFrameCaps $original -1 0}
 $hash=Get-BnqqByteHash $original
 Invoke-BnqqFramePacing $temp plan | Out-Null
 Check ((Get-BnqqByteHash ([IO.File]::ReadAllBytes($path))) -ceq $hash) 'Preview changed file'
 $applied=Invoke-BnqqFramePacing $temp apply
 Check ($applied.Status -eq 'Applied') 'Apply failed'
 Check ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($path)).Contains('"fps_max_ui$2" "120"')) 'Menu cap not changed'
 Invoke-BnqqFramePacing $temp restore -BackupFile $applied.Backup | Out-Null
 Check ((Get-BnqqByteHash ([IO.File]::ReadAllBytes($path))) -ceq $hash) 'Not byte-exact restore'
 Invoke-BnqqFramePacing $temp restore -BackupFile $applied.Backup | Out-Null
 $second=Invoke-BnqqFramePacing $temp apply
 Check ($second.Backup -ne $applied.Backup) 'Backup overwritten'
 Add-Content $path '// external edit'
 MustThrow {Invoke-BnqqFramePacing $temp restore -BackupFile $second.Backup}
 MustThrow {Convert-BnqqFrameCaps ([Text.Encoding]::ASCII.GetBytes('unknown'))}
 MustThrow {Convert-BnqqFrameCaps ([Text.Encoding]::ASCII.GetBytes('"fps_max" "0" "fps_max" "0"'))}
 [IO.File]::WriteAllBytes($path,$original)
 function Get-Process {param($Name,$ErrorAction);return [pscustomobject]@{Name='cs2'}}
 MustThrow {Invoke-BnqqFramePacing $temp apply}
 Check ((Get-BnqqByteHash ([IO.File]::ReadAllBytes($path))) -ceq $hash) 'Open-game refusal wrote file'
 'PASS: frame pacing preview, apply, byte-exact/idempotent rollback, immutable backups, schema, conflict and open-game refusal'
}finally{if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}}
