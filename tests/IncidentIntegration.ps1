#Requires -Version 5.1
# A genuinely exited PID exercises the actual recovery entrypoint, no target writes.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-incident-'+[guid]::NewGuid().ToString('N'))
$script:BnqqDataRoot=$temp
. (Join-Path $root 'lib\Core.ps1')
$file=Join-Path $temp 'journals\exited-priority.json'
$before=[pscustomobject]@{ProcessId=2147483647;Name='msedge';StartTime='2000-01-01T00:00:00.0000000Z';Priority='Normal'}
$after=$before|Select-Object *;$after.Priority='BelowNormal'
try{
 Write-BnqqAtomicJson @{Schema=2;Owner=(Get-BnqqOwner);Status='NeedsRecovery';Entries=@(@{Kind='BackgroundPriority';Before=$before;After=$after;Status='Applied'})} $file
 . (Join-Path $root 'scripts\Incident-Rollback.ps1') -BackupFile $file|Out-Null
 $r=Get-Content $file -Raw|ConvertFrom-Json
 if($r.Status -ne 'Restored' -or $r.Entries[0].Status -ne 'Exited'){throw 'Incident entrypoint did not recover new priority kind'}
 'PASS: incident script loads background-priority adapter and recovers an exited identity without mutation'
}finally{
 $full=[IO.Path]::GetFullPath($temp);$allowedRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if(-not $full.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $full -Leaf) -notlike 'bnqq-incident-*'){throw 'Unsafe incident fixture cleanup'}
 if([IO.Directory]::Exists($full)){[IO.Directory]::Delete($full,$true)}
}
