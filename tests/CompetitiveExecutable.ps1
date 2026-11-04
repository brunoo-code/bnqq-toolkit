[CmdletBinding()]
param([string]$Exe)
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
if(-not $Exe){$Exe=Join-Path $root 'dist\BNQQ_Competitive.exe'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-exe-check-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
try{
 $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName=[IO.Path]::GetFullPath($Exe);$info.Arguments='-Diagnostics';$info.WorkingDirectory=$temp;$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 # Simulate a parent application that lost Windows PowerShell module paths.
 $info.EnvironmentVariables['PSModulePath']=$temp
 $p=New-Object Diagnostics.Process;$p.StartInfo=$info;[void]$p.Start()
 try{
  $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit(30000)){$p.Kill();throw 'Own diagnostic child exceeded 30s'}
  $text=$stdout.Result;$errorText=$stderr.Result
  if($p.ExitCode -ne 0){throw ('Competitive diagnostic failed: '+$errorText)}
  $j=$text|ConvertFrom-Json
  if($j.Schema -ne 'BNQQ.CompetitiveDiagnostics.1' -or -not $j.Is64Bit -or -not $j.HashCommandAvailable){throw 'Windows PowerShell core modules missing in actual executable'}
  'PASS: actual competitive executable diagnostics with hostile inherited module path; no game launch, stress or process changes'
 }finally{$p.Dispose()}
}finally{
 $full=[IO.Path]::GetFullPath($temp);if(-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $full -Leaf) -notlike 'bnqq-exe-check-*'){throw 'Unsafe fixture cleanup'}
 if([IO.Directory]::Exists($full)){[IO.Directory]::Delete($full,$true)}
}
