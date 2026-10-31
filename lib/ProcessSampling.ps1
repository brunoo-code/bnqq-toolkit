# One process enumeration per sample; native read-only handle for identity + CPU time.
function Initialize-BnqqProcessSampler {
    if(-not ('Bnqq.ProcessTelemetry' -as [type])){Add-Type -Path (Join-Path $script:BnqqRoot 'lib\ProcessTelemetry.cs') -ErrorAction Stop}
    if(-not $script:BnqqSamplerScope){
        $p=[Diagnostics.Process]::GetCurrentProcess()
        try{
            $scope=[pscustomobject]@{Owner=(Get-BnqqOwner);Session=[uint32]$p.SessionId}
            # Compile, JIT and verify the read path during preparation, outside the polling loop.
            if(-not [Bnqq.ProcessTelemetry]::Read($p.Id,$p.ProcessName,$scope.Owner,$scope.Session)){throw 'Falha na preparacao do sampler'}
            $script:BnqqSamplerScope=$scope
        }
        finally{$p.Dispose()}
    }
}
function Get-BnqqNativeFocusSample {
    param([int]$ProcessId,[string]$Name)
    if(-not $script:BnqqSamplerScope){Initialize-BnqqProcessSampler}
    return [Bnqq.ProcessTelemetry]::Read($ProcessId,$Name,$script:BnqqSamplerScope.Owner,$script:BnqqSamplerScope.Session)
}
function Get-BnqqFocusSamples {
    param([string[]]$Apps)
    $names=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($app in @($Apps)){
        if($app -notin (Get-BnqqCpuAllowedApps)){throw 'Aplicativo focus nao admitido'}
        [void]$names.Add($app)
    }
    if(-not $names.Count){return @()}
    Initialize-BnqqProcessSampler
    $rows=New-Object 'Collections.Generic.List[object]'
    $processes=@(Get-Process -Name @($names) -ErrorAction SilentlyContinue)
    try{
        if($processes.Count -gt 128){throw 'Mais de 128 processos; sessao recusada'}
        foreach($p in $processes){
            try{
                $sample=Get-BnqqNativeFocusSample -ProcessId $p.Id -Name $p.ProcessName
                if($sample){$rows.Add($sample)}
            }catch{
                if(-not $script:BnqqFocusSampleErrors){$script:BnqqFocusSampleErrors=@{}}
                $key=[string]$p.Id+'|'+$_.Exception.Message
                if($script:BnqqFocusSampleErrors.Count -lt 128 -and -not $script:BnqqFocusSampleErrors.ContainsKey($key)){
                    $script:BnqqFocusSampleErrors[$key]=$true;Write-BnqqNightLog 'FOCUS-SAMPLE-SKIP' $key
                }
            }
        }
    }finally{foreach($p in $processes){if($p -is [IDisposable]){$p.Dispose()}}}
    return $rows.ToArray()
}
