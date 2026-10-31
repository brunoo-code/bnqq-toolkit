[CmdletBinding()]
param([string]$Exe,[string]$Payload)
$ErrorActionPreference='Stop'
if(-not $Exe){$Exe=Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\BNQQ_Optimizer.exe'}
if(-not $Payload){$Payload=Join-Path (Split-Path -Parent $PSScriptRoot) 'build\payload'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-launcher-test-'+[guid]::NewGuid().ToString('N'))
try{
    # Load managed metadata and invoke only pure verification/quoting helpers, never Main/UAC.
    $assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($Exe))
    $type=$assembly.GetType('BnqqLauncher.Program',$true)
    $flags=[Reflection.BindingFlags]'NonPublic,Static'
    $verify=$type.GetMethod('Verify',$flags);$quote=$type.GetMethod('Quote',$flags)
    $ensure=$type.GetMethod('EnsurePayload',$flags)
    $verify.Invoke($null,@([IO.Path]::GetFullPath($Payload)))|Out-Null
    $cache=Join-Path $temp 'cache'
    $extracted=[string]$ensure.Invoke($null,@([string]$cache))
    $verify.Invoke($null,@([string]$extracted))|Out-Null
    if((Get-FileHash (Join-Path $extracted 'payload.stamp')).Hash -cne (Get-FileHash (Join-Path $Payload 'payload.stamp')).Hash){throw 'Extraction changed hashed stamp bytes'}
    if([string]$ensure.Invoke($null,@([string]$cache)) -cne $extracted){throw 'Cached extraction not reused'}
    if(@(Get-ChildItem -LiteralPath $cache -Directory -Filter '*.extract-*').Count){throw 'Staging directory leaked'}
    Add-Content -LiteralPath (Join-Path $extracted 'lib\Watcher.ps1') -Value '# cached tamper fixture'
    $rejected=$false;try{$ensure.Invoke($null,@([string]$cache))|Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Tampered extracted cache was accepted'}
    foreach($case in @(@('abc','"abc"'),@('a b','"a b"'),@('','""'),@('a"b','"a\"b"'),@('a\','"a\\"'))){
        $actual=$quote.Invoke($null,@([string]$case[0]))
        if($actual -cne $case[1]){throw 'Launcher argument quoting regression'}
    }
    [void][IO.Directory]::CreateDirectory($temp)
    $copied=Join-Path $temp 'copied';[void][IO.Directory]::CreateDirectory($copied)
    Get-ChildItem -LiteralPath $Payload -Force | Copy-Item -Destination $copied -Recurse -Force
    Add-Content -LiteralPath (Join-Path $copied 'lib\Watcher.ps1') -Value '# tamper fixture'
    $rejected=$false
    try{$verify.Invoke($null,@([string]$copied))|Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Modified elevated payload was accepted'}
    Write-Host 'PASS: embedded ZIP extraction, stamp bytes, cache reuse, tamper rejection, staging cleanup and quoting; Main/UAC not executed.'
}finally{
    $full=[IO.Path]::GetFullPath($temp)
    if($full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $full -Leaf) -like 'bnqq-launcher-test-*'){
        Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
    }
}
