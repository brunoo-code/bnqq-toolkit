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
    $verify.Invoke($null,@([IO.Path]::GetFullPath($Payload)))|Out-Null
    foreach($case in @(@('abc','"abc"'),@('a b','"a b"'),@('','""'),@('a"b','"a\"b"'),@('a\','"a\\"'))){
        $actual=$quote.Invoke($null,@([string]$case[0]))
        if($actual -cne $case[1]){throw 'Launcher argument quoting regression'}
    }
    [void][IO.Directory]::CreateDirectory($temp)
    Get-ChildItem -LiteralPath $Payload -Force | Copy-Item -Destination $temp -Recurse -Force
    Add-Content -LiteralPath (Join-Path $temp 'lib\Watcher.ps1') -Value '# tamper fixture'
    $rejected=$false
    try{$verify.Invoke($null,@($temp))|Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Modified elevated payload was accepted'}
    Write-Host 'PASS: payload hashes, tamper rejection and 5 quoting cases; launcher Main not executed.'
}finally{
    $full=[IO.Path]::GetFullPath($temp)
    if($full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $full -Leaf) -like 'bnqq-launcher-test-*'){
        Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
    }
}
