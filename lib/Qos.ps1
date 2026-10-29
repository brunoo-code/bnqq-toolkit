function Get-BnqqQosPolicies {
    $base = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\QoS'
    if (-not (Test-Path -LiteralPath $base)) { return @() }

    return @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Policy      = $_.PSChildName
            Application = $props.'Application Name'
            Protocol    = $props.Protocol
            Dscp        = $props.'DSCP Value'
            Version     = $props.Version
        }
    })
}

function Get-BnqqQosPacer {
    try {
        return @(Get-NetAdapterBinding -ComponentID 'ms_pacer' -ErrorAction Stop)
    }
    catch {
        return @()
    }
}

function Set-BnqqQosDscp {
    $base = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\QoS'
    $targets = @(
        @{ Policy = 'BNQQ-CS2-DSCP46'; Application = 'cs2.exe' },
        @{ Policy = 'BNQQ-VALORANT-DSCP46'; Application = 'VALORANT-Win64-Shipping.exe' }
    )

    foreach ($target in $targets) {
        $path = Join-Path $base $target.Policy
        Set-BnqqReg $path 'Version' '1.0' 'String'
        Set-BnqqReg $path 'Application Name' $target.Application 'String'
        Set-BnqqReg $path 'Protocol' 'UDP' 'String'
        Set-BnqqReg $path 'Local Port' '*' 'String'
        Set-BnqqReg $path 'Remote Port' '*' 'String'
        Set-BnqqReg $path 'Local IP' '*' 'String'
        Set-BnqqReg $path 'Remote IP' '*' 'String'
        Set-BnqqReg $path 'Local IP Prefix Length' '*' 'String'
        Set-BnqqReg $path 'Remote IP Prefix Length' '*' 'String'
        Set-BnqqReg $path 'DSCP Value' '46' 'String'
        Set-BnqqReg $path 'Throttle Rate' '-1' 'String'
    }

    if (@(Get-BnqqQosPacer).Count -eq 0) {
        Write-Bnqq 'QoS Packet Scheduler nao vinculado; o DSCP pode nao ser aplicado' 'WARN'
    }

    Write-Bnqq 'QoS: DSCP 46 (EF) para cs2.exe e VALORANT-Win64-Shipping.exe (reboot)' 'OK'
}

function Show-BnqqQosStatus {
    $policies = @(Get-BnqqQosPolicies)
    $pacer = @(Get-BnqqQosPacer)

    Write-Host ''
    Write-Host '  QOS / DSCP' -ForegroundColor Cyan

    if ($policies.Count -eq 0) {
        Write-Host '    Politicas    nenhuma' -ForegroundColor Yellow
    }
    else {
        foreach ($policy in $policies) {
            Write-Host ('    {0}  {1}  DSCP {2}  {3}' -f $policy.Policy, $policy.Application, $policy.Dscp, $policy.Protocol) -ForegroundColor Gray
        }
    }

    if ($pacer.Count -eq 0) {
        Write-Host '    Pacer        QoS Packet Scheduler nao vinculado; DSCP pode nao ser aplicado' -ForegroundColor Yellow
    }
    else {
        Write-Host ('    Pacer        {0} adaptador(es) com QoS Packet Scheduler' -f $pacer.Count) -ForegroundColor Gray
    }

    Write-Host '    Nota         DSCP so prioriza se o roteador respeitar EF; nao reduz ping fisico' -ForegroundColor DarkGray
    Write-Host ''
}
