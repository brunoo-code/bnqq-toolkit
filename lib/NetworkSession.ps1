# Outbound-only QoS for explicitly selected sync applications. No router or NIC changes.
function Get-BnqqNetworkApps { return @('OneDrive.exe','Dropbox.exe','GoogleDriveFS.exe') }
function Get-BnqqNetPolicies {
    Import-Module NetQos -ErrorAction Stop
    return @(Get-NetQosPolicy -PolicyStore ActiveStore -ErrorAction Stop)
}
function Get-BnqqNetState {
    param($Policy)
    # Use native properties, not localized formatted ThrottleRate output. Normalize
    # provider lowercasing and null/empty strings; preserve every traffic selector/action.
    $state=[ordered]@{}
    foreach($key in @('Name','AppPathNameMatchCondition','IPDstPrefixMatchCondition','IPSrcPrefixMatchCondition','JobObjectMatchCondition','URIMatchCondition','UserMatchCondition')){
        $state[$key]=([string]$Policy.$key).ToLowerInvariant()
    }
    foreach($key in @('NetworkProfile','Precedence','DSCPAction','PriorityValue8021Action','MinBandwidthWeightAction','IPProtocolMatchCondition','IPDstPortEndMatchCondition','IPDstPortStartMatchCondition','IPPortMatchCondition','IPSrcPortEndMatchCondition','IPSrcPortStartMatchCondition','NetDirectPortMatchCondition','TemplateMatchCondition')){
        $state[$key]=[int]$Policy.$key
    }
    $state.ThrottleRateAction=[uint64]$Policy.ThrottleRateAction
    $state.URIRecursiveMatchCondition=[bool]$Policy.URIRecursiveMatchCondition
    return [pscustomobject]$state
}
function New-BnqqNetExpectedState {
    param([string]$Name,[string]$App,[uint64]$Rate)
    # Defaults verified against the native provider on Windows, including DSCP=-1.
    return (Get-BnqqNetState ([pscustomobject]@{Name=$Name;AppPathNameMatchCondition=$App;ThrottleRateAction=$Rate;NetworkProfile=7;Precedence=127;DSCPAction=-1;PriorityValue8021Action=-1}))
}
function Add-BnqqNetPolicy {
    param($Expected)
    New-NetQosPolicy -Name $Expected.Name -PolicyStore ActiveStore -NetworkProfile All -Precedence 127 -AppPathNameMatchCondition $Expected.AppPathNameMatchCondition -ThrottleRateActionBitsPerSecond $Expected.ThrottleRateAction -ErrorAction Stop | Out-Null
}
function Remove-BnqqNetPolicy {
    param([string]$Name)
    if($Name -cnotmatch '^bnqq-net-[0-9a-f]{32}-[0-2]$'){throw 'Nome de politica nao admitido'}
    # Never omit Name: doing so could remove ALL policies in this store.
    Remove-NetQosPolicy -Name $Name -PolicyStore ActiveStore -Confirm:$false -ErrorAction Stop
}
function Get-BnqqNetworkSessionPlan {
    param([string[]]$Apps,[ValidateRange(64,1000000)][int]$UploadKbps=512)
    foreach($app in @($Apps)){if($app -notin (Get-BnqqNetworkApps)){throw ('App de rede nao admitido: '+$app)}}
    return [pscustomobject]@{Apps=@($Apps|ForEach-Object {$_.ToLowerInvariant()}|Select-Object -Unique);RateBitsPerSecond=([uint64]$UploadKbps*1000);Store='ActiveStore';Direction='Outbound';Note='Limite solicitado para apps escolhidos; nao e limite global da conexao, nao limita downloads nem garante ping/FPS. Conexoes existentes podem exigir renovacao.'}
}
function Assert-BnqqNetNoOverlap {
    param([string[]]$Apps,$Policies)
    foreach($p in @($Policies)){
        $app=[string]$p.AppPathNameMatchCondition
        # Unknown/default/URI policies may overlap: fail closed. Policies for games
        # or other explicit executables remain untouched and do not block sync apps.
        if(-not $app -or $app -match '[*?\[\]]' -or [IO.Path]::GetFileName($app) -in $Apps){throw ('Politica QoS potencialmente sobreposta; nenhuma escrita: '+$p.Name)}
    }
}
function Restore-BnqqNetworkSession {
    param([Parameter(Mandatory)][string]$File)
    $item=Get-Item -LiteralPath $File -ErrorAction Stop
    if($item.Length -gt 2097152){throw 'Journal de rede grande demais'}
    $j=Get-Content -LiteralPath $File -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json
    if($j.Schema -cne 'BNQQ.NetworkSession.1' -or $j.Owner -cne (Get-BnqqOwner) -or $j.Id -cnotmatch '^[0-9a-f]{32}$' -or @($j.Entries).Count -gt 3){throw 'Journal de rede invalido ou de outro usuario'}
    # Validate the whole journal before deleting anything. Never trust executable,
    # name, selectors or actions supplied by an arbitrary JSON backup.
    for($i=0;$i -lt @($j.Entries).Count;$i++){
        $e=$j.Entries[$i];$rate=0L
        if($e.BeforeAbsent -isnot [bool] -or -not $e.BeforeAbsent -or $e.Expected.Name -cne ('bnqq-net-'+$j.Id+'-'+$i) -or $e.Expected.AppPathNameMatchCondition -notin (Get-BnqqNetworkApps) -or -not [long]::TryParse([string]$e.Expected.ThrottleRateAction,[ref]$rate) -or $rate -lt 64000 -or $rate -gt 1000000000){throw 'Transicao QoS nao admitida'}
        $expected=New-BnqqNetExpectedState $e.Expected.Name $e.Expected.AppPathNameMatchCondition $rate
        if(-not (Test-BnqqSameValue $expected $e.Expected)){throw 'Seletores/acoes QoS nao admitidos'}
    }
    $errors=@()
    foreach($e in @($j.Entries)){
        if($e.Status -eq 'Restored'){continue}
        try {
            $live=@(Get-BnqqNetPolicies|Where-Object Name -ieq $e.Expected.Name)
            if($live.Count){
                if($live.Count -ne 1 -or -not (Test-BnqqSameValue (Get-BnqqNetState $live[0]) $e.Expected)){throw 'Politica mudou externamente; nao remover'}
                Remove-BnqqNetPolicy $e.Expected.Name
            }
            if(@(Get-BnqqNetPolicies|Where-Object Name -ieq $e.Expected.Name).Count){throw 'Remocao QoS nao verificada'}
            $e.Status='Restored'
        }catch{$errors+=$_.Exception.Message}
        Write-BnqqAtomicJson $j $File
    }
    $j.Status=if($errors.Count){'NeedsRecovery'}else{'Restored'}
    Write-BnqqAtomicJson $j $File
    if($errors.Count){throw ('Recuperacao de rede pendente: '+($errors -join '; '))}
    return $j
}
function Invoke-BnqqNetworkSession {
    param([ValidateSet('plan','run','restore')][string]$Action='plan',[string[]]$Apps,
        [ValidateRange(64,1000000)][int]$UploadKbps=512,
        [ValidateSet('cs2.exe','VALORANT-Win64-Shipping.exe')][string]$Game='cs2.exe',[string]$File)
    if($Action -eq 'plan'){return (Get-BnqqNetworkSessionPlan $Apps $UploadKbps)}
    if(-not (Test-BnqqAdmin)){throw 'Sessao de rede exige administrador'}
    $plan=$null
    if($Action -eq 'run'){
        $plan=Get-BnqqNetworkSessionPlan $Apps $UploadKbps
        if(-not $plan.Apps.Count){throw 'Escolha apps; lista vazia nunca limita a conexao inteira'}
        Assert-BnqqHeavyQa -WorkloadOnly
    }
    $lock=Enter-BnqqStateLock
    try {
        if($Action -eq 'restore'){return (Restore-BnqqNetworkSession $File)}
        Assert-BnqqNoPendingJournal
        $dir=Join-Path (Get-BnqqDataRoot) 'network-sessions'
        foreach($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)){
            $old=Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8|ConvertFrom-Json
            if($old.Status -ne 'Restored'){throw ('Recupere sessao de rede anterior: '+$f.FullName)}
        }
        $games=@(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($Game)) -ErrorAction Stop)
        try {
            if($games.Count -ne 1){throw 'Uma unica instancia do jogo exigida'}
            $identity=Get-BnqqSessionProcess $games[0].Id
            if(-not $identity){throw 'Jogo encerrou antes da sessao'}
        }finally{foreach($p in $games){if($p -is [Diagnostics.Process]){$p.Dispose()}}}
        Assert-BnqqNetNoOverlap $plan.Apps @(Get-BnqqNetPolicies)
        $id=[guid]::NewGuid().ToString('N');$file=Join-Path $dir ($id+'.json')
        $j=[pscustomobject]@{Schema='BNQQ.NetworkSession.1';Owner=(Get-BnqqOwner);Id=$id;Started=[datetime]::UtcNow.ToString('o');Game=$identity;Status='Prepared';Entries=@()}
        Write-BnqqAtomicJson $j $file
        try {
            for($i=0;$i -lt $plan.Apps.Count;$i++){
                # Recheck before each write; never replace someone else's policy.
                Assert-BnqqNetNoOverlap @($plan.Apps[$i]) @(Get-BnqqNetPolicies)
                $expected=New-BnqqNetExpectedState ('bnqq-net-'+$id+'-'+$i) $plan.Apps[$i] $plan.RateBitsPerSecond
                if(@(Get-BnqqNetPolicies|Where-Object Name -ieq $expected.Name).Count){throw 'Nome QoS ocupado'}
                $entry=[pscustomobject]@{BeforeAbsent=$true;Expected=$expected;Status='Prepared'}
                $j.Entries=@($j.Entries)+@($entry);Write-BnqqAtomicJson $j $file
                Add-BnqqNetPolicy $expected
                $live=@(Get-BnqqNetPolicies|Where-Object Name -ieq $expected.Name)
                if($live.Count -ne 1 -or -not (Test-BnqqSameValue (Get-BnqqNetState $live[0]) $expected)){throw 'Politica QoS solicitada nao verificada'}
                $entry.Status='Applied';Write-BnqqAtomicJson $j $file
            }
            $j.Status='Active';Write-BnqqAtomicJson $j $file
            Write-Host ('Sessao de upload ativa; recuperacao: '+$file)
            Wait-BnqqSessionGame $identity
        }finally{Restore-BnqqNetworkSession $file|Out-Null}
        return [pscustomobject]@{Status='Restored';Journal=$file;Apps=$plan.Apps;RequestedRateBitsPerSecond=$plan.RateBitsPerSecond;TrafficMeasured=$false}
    }finally{$lock.Dispose()}
}
function Show-BnqqNetworkSessionMenu {
    Write-Host 'Limite temporario de UPLOAD dos apps escolhidos. Sem ganho presumido de FPS; nao limita downloads.'
    Write-Host ('Admitidos: '+((Get-BnqqNetworkApps)-join ', '))
    $text=Read-Host 'Apps separados por virgula; vazio cancela'
    if(-not $text.Trim()){return}
    $apps=@($text.Split(',')|ForEach-Object {$_.Trim()}|Where-Object {$_})
    $rate=0
    if(-not [int]::TryParse((Read-Host 'Limite solicitado em kbit/s por politica (64 a 1000000)'),[ref]$rate)){throw 'Limite invalido'}
    Invoke-BnqqNetworkSession -Apps $apps -UploadKbps $rate|Format-List
    $choice=Read-Host 'Jogo aberto: 1=CS2, 2=Valorant; outro cancela'
    if($choice -notin @('1','2')){return}
    $game=if($choice -eq '1'){'cs2.exe'}else{'VALORANT-Win64-Shipping.exe'}
    Write-Host 'Mantenha esta janela aberta; fecha a sessao ao sair do jogo. Ctrl+C solicita restauracao; se matar a janela, use Recuperacao.'
    Invoke-BnqqNetworkSession -Action run -Apps $apps -UploadKbps $rate -Game $game|Format-List
}
