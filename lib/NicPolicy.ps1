function Get-BnqqNicKeywords {return @('*IPChecksumOffloadIPv4','*UDPChecksumOffloadIPv4','*UDPChecksumOffloadIPv6')}
function Get-BnqqPhysicalAdapters {return @(Get-NetAdapter -Physical -ErrorAction Stop|Where-Object HardwareInterface)}
function Get-BnqqNicIdentity {
    param($Adapter)
    if(-not $Adapter.PnPDeviceID -or -not $Adapter.DriverVersion){throw 'Identidade/driver de rede incompleto'}
    return [pscustomobject]@{Guid=([guid]$Adapter.InterfaceGuid).ToString('D');Pnp=[string]$Adapter.PnPDeviceID;Driver=[string]$Adapter.DriverVersion}
}
function Show-BnqqNicMenu {
    $name=Read-Host 'Nome exato do adaptador fisico; vazio seleciona o unico conectado'
    $plan=Invoke-BnqqNicPolicy -Name $name
    $plan|Format-List
    if($plan.Entries.Count -and (Read-Host 'Salvar checksums suportados para ativar depois? Sera necessario reiniciar o adaptador manualmente; conexao nao sera interrompida agora. Digite REDE') -ceq 'REDE'){
        Invoke-BnqqNicPolicy -Action stage -Name $name|Format-List
    }
}
function Resolve-BnqqNic {
    param([string]$Name,$Identity)
    $all=@(Get-BnqqPhysicalAdapters)
    if($Identity){$found=@($all|Where-Object {([guid]$_.InterfaceGuid).ToString('D') -ieq $Identity.Guid})}
    elseif($Name){$found=@($all|Where-Object Name -ieq $Name)}
    else{$found=@($all|Where-Object Status -eq 'Up')}
    if($found.Count -ne 1){throw 'Selecione um unico adaptador fisico; nenhuma alteracao em interfaces virtuais'}
    $a=$found[0];$id=Get-BnqqNicIdentity $a
    if($Identity -and -not (Test-BnqqSameValue $id $Identity)){throw 'Adaptador/driver mudou; nao restaurar outro dispositivo'}
    return $a
}
function Get-BnqqNicProperty {
    param($Adapter,[string]$Keyword)
    if($Keyword -notin (Get-BnqqNicKeywords)){throw 'Propriedade de rede nao admitida'}
    $name=[WildcardPattern]::Escape([string]$Adapter.Name)
    $p=@(Get-NetAdapterAdvancedProperty -Name $name -AllProperties -ErrorAction Stop|Where-Object RegistryKeyword -ceq $Keyword)
    if($p.Count -gt 1){throw 'Propriedade de rede ambigua'}
    if($p.Count){return $p[0]}
    return $null
}
function Set-BnqqNicProperty {
    param($Identity,[string]$Keyword,[string[]]$Expected,[string[]]$Value)
    $a=Resolve-BnqqNic -Identity $Identity;$p=Get-BnqqNicProperty $a $Keyword
    if(-not $p -or -not (Test-BnqqSameValue @($p.RegistryValue) @($Expected)) -or $Value.Count -ne 1 -or $Value[0] -notin $p.ValidRegistryValues){throw 'Propriedade/valor de rede mudou ou nao e suportado'}
    # Exact CIM property object, never a wildcard setter or a new registry key.
    # NoRestart is mandatory: this command does not interrupt the connection.
    Set-NetAdapterAdvancedProperty -InputObject $p -RegistryValue $Value -NoRestart -Confirm:$false -ErrorAction Stop
}
function Get-BnqqNicPlan {
    param([string]$Name)
    $a=Resolve-BnqqNic -Name $Name;$id=Get-BnqqNicIdentity $a;$entries=@();$unsupported=@();$supported=0
    foreach($key in (Get-BnqqNicKeywords)){
        $p=Get-BnqqNicProperty $a $key
        if(-not $p -or @($p.RegistryValue).Count -ne 1 -or [string]$p.RegistryValue[0] -notin @('0','1','2','3') -or '3' -notin $p.ValidRegistryValues){$unsupported+=@($key);continue}
        $supported++
        if([string]$p.RegistryValue[0] -ne '3'){$entries+=@([pscustomobject]@{Keyword=$key;Before=@([string]$p.RegistryValue[0]);After=@('3');Status='Prepared'})}
    }
    return [pscustomobject]@{Status=$(if($entries.Count){'Candidate'}elseif($supported){'AlreadyConfigured'}else{'Unsupported'});Adapter=[string]$a.Name;Identity=$id;Entries=$entries;Unsupported=$unsupported;RequiresAdapterRestart=($entries.Count -gt 0);Note='Somente checksums IP/UDP suportados. Estagia configuracao sem reiniciar rede; nao comprova ativacao no miniport, menor ping ou FPS. TCP/LSO/RSS/EEE/rotas/DNS/portas preservados.'}
}
function Read-BnqqNicJournal {
    param([Parameter(Mandatory)][string]$File)
    if((Get-Item -LiteralPath $File -ErrorAction Stop).Length -gt 2097152){throw 'Journal de rede grande demais'}
    $j=Get-Content -LiteralPath $File -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json
    if($j.Schema -cne 'BNQQ.Nic.1' -or $j.Owner -cne (Get-BnqqOwner) -or @($j.Entries).Count -gt 3 -or @($j.Entries|Select-Object -ExpandProperty Keyword -Unique).Count -ne @($j.Entries).Count){throw 'Journal de adaptador invalido'}
    foreach($e in @($j.Entries)){
        if($e.Keyword -notin (Get-BnqqNicKeywords) -or @($e.Before).Count -ne 1 -or $e.Before[0] -isnot [string] -or $e.Before[0] -notin @('0','1','2','3') -or @($e.After).Count -ne 1 -or $e.After[0] -isnot [string] -or $e.After[0] -cne '3'){throw 'Transicao de rede nao admitida'}
    }
    return $j
}
function Restore-BnqqNicPolicy {
    param([Parameter(Mandatory)][string]$File)
    $j=Read-BnqqNicJournal $File
    $a=Resolve-BnqqNic -Identity $j.Identity;$errors=@()
    foreach($e in @($j.Entries)){
        if($e.Status -eq 'Restored'){continue}
        try {
            $p=Get-BnqqNicProperty $a $e.Keyword
            if(-not $p){throw 'Propriedade deixou de existir'}
            if(-not (Test-BnqqSameValue @($p.RegistryValue) @($e.Before))){
                if(-not (Test-BnqqSameValue @($p.RegistryValue) @($e.After))){throw 'Propriedade alterada externamente; nao sobrescrever'}
                Set-BnqqNicProperty $j.Identity $e.Keyword $e.After $e.Before
            }
            $check=Get-BnqqNicProperty (Resolve-BnqqNic -Identity $j.Identity) $e.Keyword
            if(-not $check -or -not (Test-BnqqSameValue @($check.RegistryValue) @($e.Before))){throw 'Restauracao da configuracao de rede nao verificada'}
            $e.Status='Restored'
        }catch{$errors+=$_.Exception.Message}
        Write-BnqqAtomicJson $j $File
    }
    $j.Status=if($errors.Count){'NeedsRecovery'}else{'Restored'}
    Write-BnqqAtomicJson $j $File
    if($errors.Count){throw ('Recuperacao de rede pendente: '+($errors -join '; '))}
    return $j
}
function Invoke-BnqqNicPolicy {
    param([ValidateSet('plan','stage','restore','activate','restore-active')][string]$Action='plan',[string]$Name,[string]$File)
    if($Action -in @('activate','restore-active')){return (Invoke-BnqqNicActivation -File $File -Restore:($Action -eq 'restore-active'))}
    if($Action -eq 'plan'){return (Get-BnqqNicPlan $Name)}
    $lock=Enter-BnqqStateLock
    try {
        if($Action -eq 'restore'){
            if(-not (Test-BnqqAdmin)){throw 'Recuperacao do adaptador exige administrador'}
            return (Restore-BnqqNicPolicy $File)
        }
        Assert-BnqqNoPendingJournal
        $plan=Get-BnqqNicPlan $Name
        if(-not $plan.Entries.Count){return $plan}
        Assert-BnqqHeavyQa -WorkloadOnly;Assert-BnqqMemoryHeadroom
        if(-not (Test-BnqqAdmin)){throw 'Configuracao do adaptador exige administrador'}
        $dir=Join-Path (Get-BnqqDataRoot) 'nic-journals'
        foreach($old in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)){
            $prior=Get-Content -LiteralPath $old.FullName -Raw -Encoding UTF8|ConvertFrom-Json
            if($prior.Schema -cne 'BNQQ.Nic.1' -or ($prior.Status -ne 'Restored' -and $prior.Identity.Guid -ieq $plan.Identity.Guid)){throw ('Restaure a configuracao anterior deste adaptador: '+$old.FullName)}
        }
        $file=Join-Path $dir ([guid]::NewGuid().ToString('N')+'.json')
        $j=[pscustomobject]@{Schema='BNQQ.Nic.1';Owner=(Get-BnqqOwner);Started=[datetime]::UtcNow.ToString('o');Identity=$plan.Identity;Status='Prepared';RequiresAdapterRestart=$true;Entries=@()}
        Write-BnqqAtomicJson $j $file
        try {
            foreach($e in @($plan.Entries)){
                $j.Entries+=@($e);Write-BnqqAtomicJson $j $file
                Set-BnqqNicProperty $j.Identity $e.Keyword $e.Before $e.After
                $live=Get-BnqqNicProperty (Resolve-BnqqNic -Identity $j.Identity) $e.Keyword
                if(-not $live -or -not (Test-BnqqSameValue @($live.RegistryValue) @($e.After))){throw 'Configuracao de rede nao verificada'}
                $e.Status='Configured';Write-BnqqAtomicJson $j $file
                Assert-BnqqPhaseHealth ([datetime]::Parse($j.Started))
            }
            $j.Status='Staged';Write-BnqqAtomicJson $j $file
            return [pscustomobject]@{Status='Staged';Journal=$file;RequiresAdapterRestart=$true;RuntimeActivation='NotAssumed';PerformanceMeasured=$false}
        }catch{
            $original=$_;$original.Exception.Data['BnqqJournal']=$file;Write-BnqqNightLog 'NIC-FAILED' $original.Exception.Message
            try{Restore-BnqqNicPolicy $file|Out-Null}catch{$_.Exception.Data['BnqqJournal']=$file;throw}
            throw $original
        }
    }finally{$lock.Dispose()}
}

function Get-BnqqNicRuntime {
    param($Identity)
    $a=Resolve-BnqqNic -Identity $Identity
    $o=@(Get-NetAdapterChecksumOffload -Name ([WildcardPattern]::Escape([string]$a.Name)) -ErrorAction Stop)
    if($o.Count -ne 1){throw 'Estado de checksum ambiguo/indisponivel'}
    $values=[ordered]@{}
    foreach($pair in @(@('*IPChecksumOffloadIPv4','IpIPv4Enabled'),@('*UDPChecksumOffloadIPv4','UdpIPv4Enabled'),@('*UDPChecksumOffloadIPv6','UdpIPv6Enabled'))){
        $v=$o[0].($pair[1])
        if($v -is [Enum]){$v=[int]$v}
        if($null -eq $v -or [string]$v -notmatch '^[0-3]$'){throw 'Estado do driver nao reconhecido; nao presumir ativacao'}
        $values[$pair[0]]=[string]$v
    }
    $routes=@(Get-NetRoute -InterfaceIndex $a.InterfaceIndex -ErrorAction Stop|Where-Object {$_.DestinationPrefix -in @('0.0.0.0/0','::/0')}|ForEach-Object {$_.DestinationPrefix+'|'+$_.NextHop}|Sort-Object -Unique)
    $global=Get-NetOffloadGlobalSetting -ErrorAction Stop
    [pscustomobject]@{Status=[string]$a.Status;Values=[pscustomobject]$values;DefaultRoutes=$routes;GlobalTaskOffload=[string]$global.TaskOffload}
}
function Restart-BnqqNic {
    param($Identity)
    $a=Resolve-BnqqNic -Identity $Identity
    Restart-NetAdapter -Name ([WildcardPattern]::Escape([string]$a.Name)) -Confirm:$false -ErrorAction Stop
}
function New-BnqqNicActivationClock {return [Diagnostics.Stopwatch]::StartNew()}
function Wait-BnqqNicRuntime {
    param($Identity,$Entries,[switch]$Original,$Routes)
    $clock=New-BnqqNicActivationClock
    $lastError='Adaptador nao retornou'
    do{
        try{
            $r=Get-BnqqNicRuntime $Identity
            if($r.Status -ne 'Up'){throw 'Link ainda nao retornou'}
            if(-not $Original -and $r.GlobalTaskOffload -cne 'Enabled'){throw 'TaskOffload global nao habilitado; nao declarar checksum ativo'}
            foreach($e in $Entries){$expected=if($Original){[string]$e.Before[0]}else{[string]$e.After[0]};if($r.Values.($e.Keyword) -cne $expected){throw ('Checksum nao confirmado pelo driver: '+$e.Keyword)}}
            if(-not (Test-BnqqSameValue @($r.DefaultRoutes) @($Routes))){throw 'Rotas padrao ainda nao retornaram; rotas nao serao reescritas'}
            return $r
        }catch{$lastError=$_.Exception.Message}
        Start-Sleep -Milliseconds 500
    }while($clock.Elapsed.TotalSeconds -lt 30)
    throw $lastError
}
function Invoke-BnqqNicActivation {
    param([Parameter(Mandatory)][string]$File,[switch]$Restore)
    if(-not (Test-BnqqAdmin)){throw 'Ativacao de rede exige administrador'}
    if(-not $Restore){Assert-BnqqHeavyQa -WorkloadOnly}
    $lock=Enter-BnqqStateLock
    try{
        $j=Read-BnqqNicJournal $File
        if(-not @($j.Entries).Count -or $j.Status -notin @('Staged','Activated','Restored')){throw 'Journal sem alteracoes ativaveis'}
        $adapter=Resolve-BnqqNic -Identity $j.Identity
        if([string]$adapter.Status -eq 'Disabled' -or (-not $Restore -and [string]$adapter.Status -ne 'Up')){throw 'Adaptador desconectado/desabilitado; nao forcar reconexao'}
        foreach($e in $j.Entries){
            $p=Get-BnqqNicProperty $adapter $e.Keyword
            $expected=if($j.Status -eq 'Restored'){@($e.Before)}else{@($e.After)}
            if(-not $p -or -not (Test-BnqqSameValue @($p.RegistryValue) $expected)){throw 'Checksum alterado externamente; nao reiniciar adaptador'}
        }
        $before=Get-BnqqNicRuntime $j.Identity;$attempted=$false
        if(-not $Restore -and $before.GlobalTaskOffload -cne 'Enabled'){throw 'TaskOffload global desabilitado/indeterminado; estado global nao sera alterado'}
        $wasActivated=$j.Status -eq 'Activated' -or ($j.Activation -and $j.Activation.State -eq 'Verified')
        $wasStaged=$j.Status -eq 'Staged'
        if($Restore){Restore-BnqqNicPolicy $File|Out-Null;$j=Read-BnqqNicJournal $File}
        elseif($j.Status -eq 'Restored'){throw 'Backup ja restaurado; nao reaplicar ajustes implicitamente'}
        $activation=[pscustomobject]@{Started=[datetime]::UtcNow.ToString('o');State='Prepared';BeforeRuntime=$before;Result=$null;Error=$null}
        $j|Add-Member -NotePropertyName Activation -NotePropertyValue $activation -Force
        Write-BnqqAtomicJson $j $File
        try{
            $matches=$true
            foreach($e in $j.Entries){$expected=if($Restore){[string]$e.Before[0]}else{[string]$e.After[0]};if($before.Values.($e.Keyword) -cne $expected){$matches=$false}}
            # CIM may mirror registry before the miniport reloads. A staged journal
            # therefore always requires one explicit reset; registry readback alone is insufficient.
            if(-not $matches -or ($wasStaged -and -not $Restore) -or ($Restore -and $wasActivated)){$activation.State='RestartPending';Write-BnqqAtomicJson $j $File;$attempted=$true;Restart-BnqqNic $j.Identity}
            $runtime=Wait-BnqqNicRuntime $j.Identity $j.Entries -Original:$Restore -Routes $before.DefaultRoutes
            if(-not $Restore){Assert-BnqqPhaseHealth ([datetime]::Parse($activation.Started))}
            $activation.State='Verified';$activation.Result=$runtime
            if(-not $Restore){$j.Status='Activated'}
            Write-BnqqAtomicJson $j $File
            [pscustomobject]@{Status=$(if($Restore){'RestoredActive'}else{'Activated'});Journal=$File;Restarted=$attempted;RuntimeActivation='DriverReportedValuesVerified';Runtime=$runtime;RequiresAdapterRestart=$false;PerformanceMeasured=$false;Note='Driver/configuracao verificados; nao comprova offload de todo pacote nem melhora de ping/FPS'}
        }catch{
            $original=$_;$activation.Error=$original.Exception.Message;$activation.State='NeedsRecovery'
            try{
                Restore-BnqqNicPolicy $File|Out-Null
                if($attempted -or $wasActivated){Restart-BnqqNic $j.Identity;Wait-BnqqNicRuntime $j.Identity $j.Entries -Original -Routes $before.DefaultRoutes|Out-Null}
                $recovered=Read-BnqqNicJournal $File;$activation.State='RolledBack';$recovered|Add-Member -NotePropertyName Activation -NotePropertyValue $activation -Force;Write-BnqqAtomicJson $recovered $File
            }catch{Write-BnqqNightLog 'NIC-ACTIVATION-RECOVERY-FAILED' $_.Exception.Message;throw}
            throw $original
        }
    }finally{$lock.Dispose()}
}
