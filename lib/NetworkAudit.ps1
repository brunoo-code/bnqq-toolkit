function Get-BnqqGameFirewallRules {
    $rules = @(Get-NetFirewallRule -DisplayName 'BNQQ-*' -ErrorAction SilentlyContinue)
    $rows = @()
    foreach ($rule in $rules) {
        $app = $null
        try {
            $filter = Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $rule -ErrorAction Stop
            $app = $filter.Program
        }
        catch { }
        $rows += [pscustomobject]@{
            Name = $rule.DisplayName
            Enabled = $rule.Enabled
            Direction = $rule.Direction
            Action = $rule.Action
            Program = $app
        }
    }
    return $rows
}

function Set-BnqqGameFirewallAllow {
    if (-not (Test-BnqqAdmin)) { throw 'Exige elevacao para criar regras de firewall' }

    $exes = @(Get-BnqqGameExes)
    if ($exes.Count -eq 0) {
        Write-Bnqq 'Firewall: nenhum executavel de jogo localizado' 'WARN'
        return
    }

    $created = 0
    foreach ($exe in $exes) {
        if (-not (Test-Path -LiteralPath $exe)) { continue }
        $name = [IO.Path]::GetFileNameWithoutExtension($exe)
        $ruleName = 'BNQQ-{0}-UDP-Out' -f $name
        if (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue) { continue }
        try {
            New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -Program $exe -Protocol UDP -Action Allow -Profile Any -ErrorAction Stop | Out-Null
            Write-Bnqq ('Firewall: regra UDP outbound para {0}' -f $name) 'OK'
            $created++
        }
        catch {
            Write-Bnqq ('Firewall: falha em {0}: {1}' -f $name, $_.Exception.Message) 'WARN'
        }
    }
    Write-Bnqq ('Firewall: {0} regra(s) criada(s); firewall nao foi desativado' -f $created) 'STEP'
}

function Get-BnqqDscpAudit {
    $policies = @(Get-BnqqQosPolicies)
    $pacer = @(Get-BnqqQosPacer)
    return [pscustomobject]@{
        Policies = $policies
        Pacer = $pacer
        WireVerified = $false
        Note = 'DSCP marcado no host; verificacao no fio exige captura no roteador/Realtek'
    }
}

function Show-BnqqNetworkAudit {
    $dscp = Get-BnqqDscpAudit
    $rules = @(Get-BnqqGameFirewallRules)

    Write-Host ''
    Write-Host '  REDE / DSCP / FIREWALL' -ForegroundColor Cyan
    if ($dscp.Policies.Count -eq 0) {
        Write-Host '    QoS         nenhuma politica DSCP' -ForegroundColor Yellow
    }
    else {
        foreach ($p in $dscp.Policies) {
            Write-Host ('    QoS         {0}  {1}  DSCP {2}' -f $p.Policy, $p.Application, $p.Dscp) -ForegroundColor Gray
        }
    }
    Write-Host ('    Pacer       {0} adaptador(es) com ms_pacer' -f $dscp.Pacer.Count) -ForegroundColor Gray
    Write-Host ('    Firewall    {0} regra(s) BNQQ' -f $rules.Count) -ForegroundColor Gray
    foreach ($r in $rules) {
        Write-Host ('      {0}  {1}  {2}' -f $r.Name, $r.Direction, $r.Action) -ForegroundColor DarkGray
    }
    Write-Host '    DSCP no fio nao e verificado por este modulo; nao desativamos o firewall' -ForegroundColor DarkGray
    Write-Host ''
}
