function Initialize-BnqqNvidia {
    if(-not [Environment]::Is64BitProcess){throw 'NVAPI exige PowerShell x64'}
    $dll=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'nvapi64.dll'
    if(-not (Test-Path -LiteralPath $dll -PathType Leaf)){throw 'Biblioteca NVIDIA instalada nao encontrada'}
    $signature=Get-AuthenticodeSignature -LiteralPath $dll -ErrorAction Stop
    if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'NVIDIA|Microsoft'){throw 'Assinatura da biblioteca NVIDIA nao validada'}
    if(-not ('Bnqq.NvidiaDriver' -as [type])){Add-Type -Path @((Join-Path $script:BnqqRoot 'lib\NvidiaDriver.cs'),(Join-Path $script:BnqqRoot 'lib\NvidiaTelemetry.cs')) -ErrorAction Stop}
    return (Get-FileHash -LiteralPath $dll -Algorithm SHA256 -ErrorAction Stop).Hash
}
function New-BnqqNvidiaClient {return (New-Object Bnqq.NvidiaDriver)}
function Get-BnqqGpuSupport {
    $observed=@();$errors=@()
    try{$observed=@(Get-CimInstance Win32_VideoController -OperationTimeoutSec 5 -ErrorAction Stop|Select-Object Name,PNPDeviceID,DriverVersion)}catch{$errors+=$_.Exception.Message}
    $client=$null
    try {
        $hash=Initialize-BnqqNvidia;$client=New-BnqqNvidiaClient
        return [pscustomobject]@{Status='NvidiaAvailable';Provider='NVAPI';Gpus=@($client.Inventory());LibraryHash=$hash;Observed=$observed;Errors=$errors}
    }catch{return [pscustomobject]@{Status='Unavailable';Provider='None';Gpus=@();LibraryHash=$null;Observed=$observed;Errors=@($errors)+@($_.Exception.Message)}}
    finally{if($client){$client.Dispose()}}
}
function Resolve-BnqqGpuGamePath {
    param([ValidateSet('cs2.exe','VALORANT-Win64-Shipping.exe')][string]$Game='cs2.exe',[string]$Path)
    if($Path){
        if(-not [IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\') -or [IO.Path]::GetFileName($Path) -ine $Game -or -not (Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Executavel local do jogo invalido'}
        return (Get-Item -LiteralPath $Path -ErrorAction Stop).FullName
    }
    $candidates=@()
    foreach($p in @(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($Game)) -ErrorAction SilentlyContinue)){
        try{if($p.Path){$candidates+=@($p.Path)}}catch{}finally{$p.Dispose()}
    }
    if($Game -eq 'cs2.exe'){
        $roots=@((Join-Path ${env:ProgramFiles(x86)} 'Steam'))
        $steam=Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
        if($steam.SteamPath){$roots+=@([string]$steam.SteamPath)}
        foreach($root in @($roots|Select-Object -Unique)){
            $vdf=Join-Path $root 'steamapps\libraryfolders.vdf'
            if(Test-Path -LiteralPath $vdf -PathType Leaf){
                if((Get-Item -LiteralPath $vdf).Length -gt 1048576){throw 'Inventario Steam grande demais'}
                foreach($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw),'"path"\s+"([^"\r\n]+)"')){$roots+=@($m.Groups[1].Value.Replace('\\','\'))}
            }
        }
        if($roots.Count -gt 32){throw 'Muitas bibliotecas Steam; informe o executavel'}
        foreach($root in @($roots|Select-Object -Unique)){$candidates+=@(Join-Path $root 'steamapps\common\Counter-Strike Global Offensive\game\bin\win64\cs2.exe')}
    }else{
        $candidates+=@('C:\Riot Games\VALORANT\live\ShooterGame\Binaries\Win64\VALORANT-Win64-Shipping.exe')
        $meta=Join-Path $env:ProgramData 'Riot Games\Metadata\valorant.live\valorant.live.product_settings.yaml'
        if(Test-Path -LiteralPath $meta -PathType Leaf){
            if((Get-Item -LiteralPath $meta).Length -gt 65536){throw 'Metadados Riot grandes demais'}
            $m=[regex]::Match((Get-Content -LiteralPath $meta -Raw),'(?m)^product_install_full_path:\s*["'']?([^\r\n"'']+)')
            if($m.Success){$candidates+=@(Join-Path $m.Groups[1].Value.Trim() 'ShooterGame\Binaries\Win64\VALORANT-Win64-Shipping.exe')}
        }
    }
    $found=@($candidates|Where-Object {$_ -and [IO.Path]::IsPathRooted($_) -and -not $_.StartsWith('\\') -and [IO.Path]::GetFileName($_) -ieq $Game -and (Test-Path -LiteralPath $_ -PathType Leaf)}|ForEach-Object {[IO.Path]::GetFullPath($_)}|Sort-Object -Unique)
    if($found.Count -gt 1){throw 'Mais de um executavel encontrado; informe -GameExecutable'}
    if($found.Count){return $found[0]}
    return $null
}
function ConvertTo-BnqqGpuState {
    param($Profile,[string]$Hash)
    $s=@($Profile.Settings|Where-Object Id -eq 274197361)
    if($s.Count -ne 1){throw 'Estado de energia NVIDIA ausente/ambiguo'}
    $s=$s[0]
    return [pscustomobject]@{Application=[string]$Profile.Application;Profile=[string]$Profile.Name;DriverVersion=[long]$Profile.DriverVersion;LibraryHash=$Hash;Applications=@($Profile.Applications|ForEach-Object {$_.ToLowerInvariant()}|Sort-Object);Found=[bool]$s.Found;LocalOverride=[bool]($s.Found -and $s.Location -eq 0 -and $s.CurrentPredefined -eq 0);Value=[long]$s.Value;Location=[int]$s.Location;CurrentPredefined=[int]$s.CurrentPredefined;Available=@($s.Available|Sort-Object -Unique);CapabilityStatus=[int]$s.CapabilityStatus}
}
function Get-BnqqGpuState {
    param([string]$Application)
    $hash=Initialize-BnqqNvidia;$client=New-BnqqNvidiaClient
    try{return (ConvertTo-BnqqGpuState ($client.ReadProfile($Application)) $hash)}finally{$client.Dispose()}
}
function Test-BnqqGpuIdentity {
    param($A,$B)
    return ($A.Application -ceq $B.Application -and $A.Profile -ceq $B.Profile -and $A.DriverVersion -eq $B.DriverVersion -and $A.LibraryHash -ceq $B.LibraryHash -and (Test-BnqqSameValue $A.Applications $B.Applications))
}
function Assert-BnqqGpuScope {
    param($State,[string]$Game)
    $allowed=if($Game -ieq 'cs2.exe'){@('cs2.exe','csgos2.exe')}else{@('valorant-win64-shipping.exe','valorant.exe')}
    if(-not $State.Profile -or -not @($State.Applications).Count -or @($State.Applications|Where-Object {[IO.Path]::GetFileName($_) -notin $allowed}).Count){throw 'Perfil NVIDIA compartilha apps fora da familia admitida; nenhuma escrita'}
}
function Get-BnqqGpuPlan {
    param([ValidateSet('cs2.exe','VALORANT-Win64-Shipping.exe')][string]$Game='cs2.exe',[string]$GameExecutable)
    $support=Get-BnqqGpuSupport
    if($support.Status -ne 'NvidiaAvailable' -or @($support.Gpus).Count -ne 1){return [pscustomobject]@{Status='Unsupported';Support=$support;WouldChange=$false}}
    $path=Resolve-BnqqGpuGamePath $Game $GameExecutable;$query=if($path){$path}else{$Game}
    $state=Get-BnqqGpuState $query;Assert-BnqqGpuScope $state $Game
    $supported=$state.Found -and $state.CapabilityStatus -eq 0 -and 1 -in $state.Available -and $state.Value -in $state.Available
    $status=if(-not $supported){'UnsupportedSetting'}elseif($state.Value -eq 1){'AlreadyMaxPerformance'}elseif(-not $path){'ExecutableRequired'}else{'Candidate'}
    return [pscustomobject]@{Status=$status;Game=$Game;Executable=$path;Before=$state;AfterValue=1;WouldChange=($status -eq 'Candidate');Note='Somente modo de energia do perfil existente; sem overclock, fila oculta, Reflex ou alteracao global. Pode aumentar consumo e temperatura; ganho depende do gargalo.'}
}
function Set-BnqqGpuState {
    param($Expected,[ValidateSet('max','restore')][string]$Mode,$Before)
    $hash=Initialize-BnqqNvidia;$client=New-BnqqNvidiaClient
    try {
        $live=ConvertTo-BnqqGpuState ($client.ReadProfile($Expected.Application)) $hash
        if(-not (Test-BnqqSameValue $live $Expected)){throw 'Perfil mudou entre leitura e escrita'}
        if($Mode -eq 'max'){$client.Stage(274197361,1)}
        elseif($Before.LocalOverride){$client.Stage(274197361,[uint32]$Before.Value)}
        else{$client.StageRemoveOverride(274197361)}
        $client.Save()
    }finally{$client.Dispose()}
}
function Restore-BnqqGpuProfile {
    param([Parameter(Mandatory)][string]$File)
    if((Get-Item -LiteralPath $File -ErrorAction Stop).Length -gt 2097152){throw 'Backup NVIDIA grande demais'}
    $j=Get-Content -LiteralPath $File -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json
    if($j.Schema -cne 'BNQQ.Nvidia.1' -or $j.Owner -cne (Get-BnqqOwner) -or $j.Game -notin @('cs2.exe','VALORANT-Win64-Shipping.exe') -or $j.AfterValue -ne 1 -or $j.Before.LocalOverride -isnot [bool] -or $j.Before.Found -isnot [bool] -or -not $j.Before.Found -or $j.Before.Value -notin $j.Before.Available -or $j.Before.LibraryHash -cnotmatch '^[A-F0-9]{64}$'){throw 'Journal NVIDIA invalido'}
    if(-not [IO.Path]::IsPathRooted($j.Before.Application) -or $j.Before.Application.StartsWith('\\') -or [IO.Path]::GetFileName($j.Before.Application) -ine $j.Game){throw 'Alvo de recuperacao NVIDIA invalido'}
    Assert-BnqqGpuScope $j.Before $j.Game
    $live=Get-BnqqGpuState $j.Before.Application
    if(-not (Test-BnqqGpuIdentity $live $j.Before)){throw 'Driver, biblioteca ou associacoes mudaram; nao restaurar defaults presumidos'}
    $restored=($live.LocalOverride -eq $j.Before.LocalOverride -and (-not $live.LocalOverride -or $live.Value -eq $j.Before.Value))
    if(-not $restored){
        if(-not $live.LocalOverride -or $live.Value -ne 1){throw 'Perfil alterado externamente; nao sobrescrever'}
        Set-BnqqGpuState $live 'restore' $j.Before
        $after=Get-BnqqGpuState $j.Before.Application
        if(-not (Test-BnqqGpuIdentity $after $j.Before) -or $after.LocalOverride -ne $j.Before.LocalOverride -or ($j.Before.LocalOverride -and $after.Value -ne $j.Before.Value)){throw 'Restauracao NVIDIA nao verificada'}
    }
    $j.Status='Restored';Write-BnqqAtomicJson $j $File;return $j
}
function Invoke-BnqqGpuProfile {
    param([ValidateSet('status','plan','apply','restore')][string]$Action='plan',
        [ValidateSet('cs2.exe','VALORANT-Win64-Shipping.exe')][string]$Game='cs2.exe',[string]$GameExecutable,[string]$File)
    if($Action -eq 'status'){return (Get-BnqqGpuSupport)}
    if($Action -eq 'plan'){return (Get-BnqqGpuPlan $Game $GameExecutable)}
    $lock=Enter-BnqqStateLock
    try {
        if($Action -eq 'restore'){return (Restore-BnqqGpuProfile $File)}
        Assert-BnqqNoPendingJournal
        $dir=Join-Path (Get-BnqqDataRoot) 'nvidia-journals'
        foreach($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)){
            $old=Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8|ConvertFrom-Json
            if($old.Schema -cne 'BNQQ.Nvidia.1' -or ($old.Status -ne 'Restored' -and $old.Game -ieq $Game)){throw ('Recupere o perfil NVIDIA anterior deste jogo: '+$f.FullName)}
        }
        $plan=Get-BnqqGpuPlan $Game $GameExecutable
        if(-not $plan.WouldChange){return $plan}
        Assert-BnqqHeavyQa
        if(-not (Test-BnqqAdmin)){throw 'Gravacao do perfil NVIDIA exige administrador'}
        $blocked=@(Get-Process -Name cs2,VALORANT-Win64-Shipping,nvcplui,nvidiaProfileInspector -ErrorAction SilentlyContinue)
        try{if($blocked.Count){throw 'Feche jogos e editores de perfil antes de gravar; nenhum processo sera encerrado'}}
        finally{foreach($p in $blocked){if($p -is [Diagnostics.Process]){$p.Dispose()}}}
        $file=Join-Path $dir ([guid]::NewGuid().ToString('N')+'.json')
        $j=[pscustomobject]@{Schema='BNQQ.Nvidia.1';Owner=(Get-BnqqOwner);Game=$Game;Started=[datetime]::UtcNow.ToString('o');Status='Prepared';Before=$plan.Before;AfterValue=1}
        Write-BnqqAtomicJson $j $file
        try {
            Set-BnqqGpuState $plan.Before 'max'
            $after=Get-BnqqGpuState $plan.Before.Application
            if(-not (Test-BnqqGpuIdentity $after $plan.Before) -or -not $after.LocalOverride -or $after.Value -ne 1){throw 'Gravacao NVIDIA nao verificada'}
            Assert-BnqqPhaseHealth ([datetime]::Parse($j.Started))
            $j.Status='Applied';Write-BnqqAtomicJson $j $file
            return [pscustomobject]@{Status='Applied';Journal=$file;Profile=$after.Profile;Value=$after.Value;PerformanceMeasured=$false}
        }catch{
            $original=$_;$original.Exception.Data['BnqqJournal']=$file;Write-BnqqNightLog 'GPU-FAILED' $original.Exception.Message
            try{Restore-BnqqGpuProfile $file|Out-Null}
            catch{
                $_.Exception.Data['BnqqJournal']=$file;$j.Status='NeedsRecovery';Write-BnqqAtomicJson $j $file
                Write-BnqqNightLog 'GPU-RECOVERY-FAILED' $_.Exception.Message;throw
            }
            throw $original
        }
    }finally{$lock.Dispose()}
}
function Get-BnqqShaderCacheAudit {
    $hash=Initialize-BnqqNvidia;$client=New-BnqqNvidiaClient
    try {
        $base=$client.ReadProfile('');$size=@($base.Settings|Where-Object Id -eq 11306135)[0];$legacy=@($base.Settings|Where-Object Id -eq 1675263)[0]
        return [pscustomobject]@{Provider='NVAPI';Profile=$base.Name;Driver=$base.DriverVersion;LibraryHash=$hash;CapacitySettingFound=$size.Found;CapacityRawValue=$size.Value;LegacyEnableSettingFound=$legacy.Found;Action='Preserve';CacheFilesDeleted=0;Note='Nao limpar cache antes de jogar; chave legada ausente nao significa cache desativado. Valor de configuracao nao mede cache hits ou stutter.'}
    }finally{$client.Dispose()}
}
function Start-BnqqGpuRecorder {
    param([int]$Seconds)
    $hash=Initialize-BnqqNvidia
    return [pscustomobject]@{Native=(New-Object Bnqq.NvidiaTelemetry($Seconds));LibraryHash=$hash}
}
function Stop-BnqqGpuRecorder {
    param($Recorder)
    try {
        $data=$Recorder.Native.Finish()
        return [pscustomobject]@{Schema=1;Provider='NVAPI';LibraryHash=$Recorder.LibraryHash;IntervalMs=$data.IntervalMs;DeviceWide=$true;Status=$data.Status;Error=$data.Error;Started=$data.Started;Stopped=$data.Stopped;Gpus=@($data.Gpus);Samples=@($data.Samples);Claim='Device-wide sensors, not per-frame GPU time, input latency or attribution of game stutters'}
    }finally{$Recorder.Native.Dispose()}
}
function Show-BnqqGpuMenu {
    $support=Invoke-BnqqGpuProfile -Action status
    $support|Format-List
    if($support.Status -ne 'NvidiaAvailable'){return}
    $choice=Read-Host 'Perfil do driver: 1=CS2, 2=Valorant; outro cancela'
    if($choice -notin @('1','2')){return}
    $game=if($choice -eq '1'){'cs2.exe'}else{'VALORANT-Win64-Shipping.exe'}
    $plan=Invoke-BnqqGpuProfile -Game $game
    $plan|Format-List
    if($plan.WouldChange -and (Read-Host 'Aplicar modo de energia somente neste perfil existente? Digite GPU') -ceq 'GPU'){
        Invoke-BnqqGpuProfile -Action apply -Game $game|Format-List
    }
}
