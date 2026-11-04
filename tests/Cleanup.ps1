#Requires -Version 5.1
# Only owned temporary fixtures. Never empties the host recycle bin.
$ErrorActionPreference='Stop';$script:BnqqRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $script:BnqqRoot 'lib\Core.ps1');. (Join-Path $script:BnqqRoot 'lib\Cleanup.ps1')
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath());$temp=[IO.Path]::GetFullPath((Join-Path $base ('bnqq-clean-test-'+[guid]::NewGuid().ToString('N'))))
if(-not $temp.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture'}
$script:BnqqDataRoot=Join-Path $temp 'reports';$scope=Join-Path $temp 'scope';$outside=Join-Path $temp 'outside'
function Get-BnqqCleanupRoots {$scope}
$script:recycle=2;$script:emptied=0;$script:checks=0
function Get-BnqqRecycleInfo {[pscustomobject]@{Items=$script:recycle}}
function Clear-BnqqUserRecycleBin {$script:emptied++;$script:recycle=0}
function Check($ok,$msg){if(-not $ok){throw $msg};$script:checks++}
function NewFixture($relative,$old=$true){$p=Join-Path $scope $relative;[void][IO.Directory]::CreateDirectory((Split-Path $p -Parent));[IO.File]::WriteAllText($p,'owned fixture');if($old){[IO.File]::SetLastWriteTimeUtc($p,[datetime]::UtcNow.AddDays(-3))};$p}
$locked=$null;$junction=$null;$ro=$null;$script:gameOpen=$false
function Get-Process {param($Name,$ErrorAction);if($script:gameOpen){[pscustomobject]@{Name='VALORANT'}}}
try{
 [void][IO.Directory]::CreateDirectory($outside)
 $old=NewFixture 'old.tmp';$recent=NewFixture 'recent.tmp' $false
 $shader=NewFixture 'DXCache\old.bin';$riot=NewFixture 'Riot Games\old.tmp';$clip=NewFixture 'codex-clipboard-old.png';$dump=NewFixture 'crash.dmp'
 $ro=NewFixture 'readonly.tmp';[IO.File]::SetAttributes($ro,[IO.FileAttributes]::ReadOnly)
 $busy=NewFixture 'busy.tmp';$locked=[IO.File]::Open($busy,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 $changed=NewFixture 'changed.tmp'
 $plan=Get-BnqqCleanupPlan
 Check ($plan.EligibleFiles -eq 3 -and [IO.File]::Exists($old)) 'Preview mutated or included protected/recent files'
 $snapshot=$plan.Files|Where-Object Path -eq $changed;[IO.File]::AppendAllText($changed,'new data')
 $r=[Bnqq.CleanupFilesV1]::DeleteOld($changed,$scope,$snapshot.Length,$snapshot.Written,$snapshot.Created,$plan.CutoffTicks)
 Check ($r -eq 'ChangedOrRecent' -and [IO.File]::Exists($changed)) 'Changed target deleted'
 $foreign=Join-Path $outside 'outside.tmp';[IO.File]::WriteAllText($foreign,'outside fixture');[IO.File]::SetLastWriteTimeUtc($foreign,[datetime]::UtcNow.AddDays(-3));$f=Get-Item $foreign
 $r=[Bnqq.CleanupFilesV1]::DeleteOld($foreign,$scope,$f.Length,$f.LastWriteTimeUtc.Ticks,$f.CreationTimeUtc.Ticks,$plan.CutoffTicks)
 Check ($r -eq 'RefusedScope' -and [IO.File]::Exists($foreign)) 'Out-of-root target deleted'
 $junction=Join-Path $scope 'linked';New-Item -ItemType Junction -Path $junction -Target $outside|Out-Null
 $alias=Join-Path $junction 'outside.tmp';$r=[Bnqq.CleanupFilesV1]::DeleteOld($alias,$scope,$f.Length,$f.LastWriteTimeUtc.Ticks,$f.CreationTimeUtc.Ticks,$plan.CutoffTicks)
 Check ($r -eq 'RefusedFinalPath' -and [IO.File]::Exists($foreign)) 'Junction escape followed'
 $hard=Join-Path $scope 'hard.tmp';New-Item -ItemType HardLink -Path $hard -Target $foreign|Out-Null
 $f=Get-Item $hard;$r=[Bnqq.CleanupFilesV1]::DeleteOld($hard,$scope,$f.Length,$f.LastWriteTimeUtc.Ticks,$f.CreationTimeUtc.Ticks,$plan.CutoffTicks)
 Check ($r -eq 'ProtectedAttributesOrLinks') 'Hard-linked file deleted'
 $a=Invoke-BnqqCleanup -Action apply
 Check ($a.DeletedFiles -eq 1 -and $a.DeletedBytes -eq 13 -and -not [IO.File]::Exists($old)) 'Real native deletion/report mismatch'
 foreach($p in @($recent,$shader,$riot,$clip,$dump,$ro,$busy,$foreign,$hard)){Check ([IO.File]::Exists($p)) ('Protected/in-use file removed: '+$p)}
 Check ($a.SkippedFiles -eq 2 -and $a.RecycleBin -eq 'NotRequested' -and $script:emptied -eq 0) 'Skip/recycle opt-in wrong'
 Check ([IO.File]::Exists($a.Report) -and (Get-Content $a.Report -Raw|ConvertFrom-Json).Status -eq 'CompletedWithSkips') 'Report not durable'
 $locked.Dispose();$locked=$null
 $b=Invoke-BnqqCleanup -Action apply -EmptyRecycleBin
 Check ($b.DeletedFiles -eq 1 -and $b.RecycleBin -eq 'Emptied' -and $script:emptied -eq 1) 'Unlocked file/recycle mock not handled'
 $c=Invoke-BnqqCleanup -Action apply -EmptyRecycleBin
 Check ($c.DeletedFiles -eq 0 -and $c.RecycleBin -eq 'AlreadyEmpty' -and $script:emptied -eq 1) 'Repeat is not idempotent'
 $script:gameOpen=$true;$refused=$false;try{Invoke-BnqqCleanup -Action apply|Out-Null}catch{$refused=$true};Check $refused 'Cleanup during a game was not refused'
 "PASS: cleanup $script:checks checks; real handle deletion, locks, age, cache/dump protection, hardlinks, junctions, root scope, durable report, recycle opt-in"
}finally{
 if($locked){$locked.Dispose()}
 if([IO.Path]::GetFullPath($temp) -ne $temp -or -not $temp.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
 if($junction -and [IO.Directory]::Exists($junction)){[IO.Directory]::Delete($junction,$false)}
 if($ro -and [IO.File]::Exists($ro)){[IO.File]::SetAttributes($ro,[IO.FileAttributes]::Normal)}
 if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
}
