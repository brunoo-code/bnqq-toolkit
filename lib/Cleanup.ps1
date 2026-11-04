# Removes old temporary files only. No cache purge, services, game changes or resident worker.
function Initialize-BnqqCleanup {
 if(-not ('Bnqq.CleanupFilesV1' -as [type])){Add-Type -Path (Join-Path $script:BnqqRoot 'lib\CleanupFiles.cs') -ErrorAction Stop}
}
function Get-BnqqCleanupRoots {
 @((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Temp'),(Join-Path ([Environment]::GetFolderPath('Windows')) 'Temp'))|Sort-Object -Unique
}
function Get-BnqqRecycleInfo {
 $shell=New-Object -ComObject Shell.Application;$bin=$shell.Namespace(10)
 if($null -eq $bin){throw 'Lixeira indisponivel'}
 [pscustomobject]@{Items=[int]$bin.Items().Count;BytesNotEstimated=$true}
}
function Clear-BnqqUserRecycleBin {Clear-RecycleBin -Force -ErrorAction Stop}
function Get-BnqqCleanupPlan {
 param([ValidateRange(2,90)][int]$MinimumAgeDays=2)
 Initialize-BnqqCleanup
 $cutoff=[datetime]::UtcNow.AddDays(-$MinimumAgeDays);$files=New-Object 'Collections.Generic.List[object]';$issues=New-Object 'Collections.Generic.List[string]'
 $visited=0;$dirs=0;$protected=0;$recent=0;$truncated=$false;$clock=[Diagnostics.Stopwatch]::StartNew()
 $working=[IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\')
 foreach($root in @(Get-BnqqCleanupRoots)){
  $full=[IO.Path]::GetFullPath($root).TrimEnd('\');if($full.Length -lt 4){throw 'Raiz de limpeza invalida'}
  if(-not [IO.Directory]::Exists($full)){continue}
  $queue=New-Object 'Collections.Generic.Queue[string]';$queue.Enqueue($full)
  while($queue.Count){
   if($visited -ge 50000 -or $dirs -ge 8192 -or $clock.Elapsed.TotalSeconds -ge 20){$truncated=$true;break}
   $dir=$queue.Dequeue();$dirs++
   try{
    $info=Get-Item -LiteralPath $dir -Force -ErrorAction Stop
    if($info.Attributes -band [IO.FileAttributes]::ReparsePoint){$protected++;continue}
    # Preserve a current working directory and everything below it when it is inside temp.
    if($dir -ieq $working -or $dir.StartsWith(($working+'\'),[StringComparison]::OrdinalIgnoreCase)){$protected++;continue}
    foreach($entry in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)){
     $visited++;if($visited -gt 50000){$truncated=$true;break}
     $path=[IO.Path]::GetFullPath($entry.FullName)
     if(-not $path.StartsWith(($full+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Entrada fora da raiz'}
     $relative=$path.Substring($full.Length+1)
     if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -or [Bnqq.CleanupFilesV1]::Protected($relative)){$protected++;continue}
     if($entry.PSIsContainer){$queue.Enqueue($path);continue}
     if(($entry.Attributes -band [IO.FileAttributes]::ReadOnly) -or $entry.LastWriteTimeUtc -ge $cutoff){$recent++;continue}
     $files.Add([pscustomobject]@{Path=$path;Root=$full;Length=[long]$entry.Length;Written=$entry.LastWriteTimeUtc.Ticks;Created=$entry.CreationTimeUtc.Ticks})
    }
   }catch{if($issues.Count -lt 64){$issues.Add($dir+': '+$_.Exception.Message)}}
  }
  if($truncated){break}
 }
 $recycle=$null;try{$recycle=Get-BnqqRecycleInfo}catch{$issues.Add('Lixeira: '+$_.Exception.Message)}
 [pscustomobject]@{Status='Preview';MinimumAgeDays=$MinimumAgeDays;CutoffUtc=$cutoff.ToString('o');CutoffTicks=$cutoff.Ticks;Files=@($files.ToArray());EligibleFiles=$files.Count;EligibleBytes=[long](($files|Measure-Object Length -Sum).Sum);ProtectedEntries=$protected;RecentOrReadOnly=$recent;Visited=$visited;Truncated=$truncated;Issues=@($issues.ToArray());RecycleBin=$recycle;Irreversible=$true;FpsGainPromised=$false}
}
function Invoke-BnqqCleanup {
 param([ValidateSet('plan','apply')][string]$Action='plan',[ValidateRange(2,90)][int]$MinimumAgeDays=2,[switch]$EmptyRecycleBin)
 if($Action -eq 'apply' -and (Get-Process -Name cs2,'VALORANT-Win64-Shipping',VALORANT -ErrorAction SilentlyContinue)){throw 'Limpeza antes da partida: feche o jogo normalmente. Nenhum processo sera encerrado.'}
 $plan=Get-BnqqCleanupPlan -MinimumAgeDays $MinimumAgeDays
 if($Action -eq 'plan'){return ($plan|Select-Object * -ExcludeProperty Files,CutoffTicks)}
 $lock=Enter-BnqqStateLock
 try{
  $file=Join-Path (Get-BnqqDataRoot) ('cleanup\'+[guid]::NewGuid().ToString('N')+'.json')
  $report=[pscustomobject]@{Schema='BNQQ.Cleanup.1';Owner=(Get-BnqqOwner);Started=[datetime]::UtcNow.ToString('o');Status='Running';MinimumAgeDays=$MinimumAgeDays;EligibleFiles=$plan.EligibleFiles;EligibleBytes=$plan.EligibleBytes;DeletedFiles=0;DeletedBytes=[long]0;SkippedFiles=0;Failures=@();RecycleBin='NotRequested';ProtectedEntries=$plan.ProtectedEntries;ScanTruncated=$plan.Truncated;ScanIssues=$plan.Issues;Irreversible=$true;RebootRequired=$false;FpsGainPromised=$false}
  # Durable activity report, not a backup or rollback claim for deleted files.
  Write-BnqqAtomicJson $report $file
  foreach($e in $plan.Files){
   try{$result=[Bnqq.CleanupFilesV1]::DeleteOld($e.Path,$e.Root,$e.Length,$e.Written,$e.Created,$plan.CutoffTicks)}catch{$result=$_.Exception.Message}
   if($result -ceq 'Deleted'){$report.DeletedFiles++;$report.DeletedBytes+=$e.Length}else{$report.SkippedFiles++;if($report.Failures.Count -lt 64){$report.Failures+=@([pscustomobject]@{File=$e.Path;Reason=$result})}}
  }
  if($EmptyRecycleBin){
   try{if((Get-BnqqRecycleInfo).Items -eq 0){$report.RecycleBin='AlreadyEmpty'}else{Clear-BnqqUserRecycleBin;$report.RecycleBin=if((Get-BnqqRecycleInfo).Items -eq 0){'Emptied'}else{'PartiallyEmptied'}}}catch{$report.RecycleBin='Failed: '+$_.Exception.Message}
  }
  $report.Status=if($report.ScanIssues.Count -or $report.SkippedFiles -or $report.ScanTruncated -or $report.RecycleBin -like 'Failed:*' -or $report.RecycleBin -eq 'PartiallyEmptied'){'CompletedWithSkips'}else{'Completed'}
  Write-BnqqAtomicJson $report $file
  $report|Add-Member NoteProperty Report $file -PassThru
 }finally{$lock.Dispose()}
}
function Show-BnqqCleanupMenu {
 Invoke-BnqqCleanup -Action plan|Format-List
 Write-Host 'Exclusao definitiva: temporarios com mais de 48h. Arquivos recentes/em uso, caches e recuperacao sao preservados.'
 $choice=Read-Host '[1] Somente temporarios [2] Temporarios e esvaziar Lixeira [0] Cancelar'
 if($choice -notin @('1','2')){return}
 if((Read-Host 'Sem rollback dos arquivos apagados. Digite LIMPAR para executar') -ceq 'LIMPAR'){Invoke-BnqqCleanup -Action apply -EmptyRecycleBin:($choice -eq '2')|Format-List}
}
