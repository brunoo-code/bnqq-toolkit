# Windows PowerShell 5.1. No changes are performed by importing this file.
function Get-BnqqDataRoot {
    if ($script:BnqqDataRoot) { return $script:BnqqDataRoot }
    return (Join-Path $env:LOCALAPPDATA 'BNQQ\data')
}
function Test-BnqqAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Write-Bnqq { param([string]$Message,[string]$Level='INFO'); Write-Host "[$Level] $Message" }
function Write-BnqqAtomicJson {
    param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Path)
    $full=[IO.Path]::GetFullPath($Path)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full))
    $temp=$full+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes(($Value | ConvertTo-Json -Depth 30))
        $s=New-Object IO.FileStream($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $s.Write($bytes,0,$bytes.Length); $s.Flush($true) } finally { $s.Dispose() }
        if ([IO.File]::Exists($full)) { [IO.File]::Replace($temp,$full,($full+'.previous'),$true) }
        else { [IO.File]::Move($temp,$full) }
    } finally { if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)} }
}
function Get-BnqqOwner { return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
function Enter-BnqqStateLock {
    $dir=Get-BnqqDataRoot
    [void][IO.Directory]::CreateDirectory($dir)
    try { return (New-Object IO.FileStream((Join-Path $dir 'state.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)) }
    catch { throw 'Outro BNQQ esta usando o estado. Aguarde a conclusao ou encerre cooperativamente o watcher.' }
}
function Get-BnqqRegistryTargets {
    # Only this documented recording policy is currently admitted for persistent experiments.
    return @([pscustomobject]@{Id='recording-off';Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR';Name='AllowGameDVR';Value=0;Type='DWord'})
}
function Get-RegSnapshot {
    param([string]$Path,[string]$Name)
    if(-not (Test-Path -LiteralPath $Path -ErrorAction Stop)){return [pscustomobject]@{Path=$Path;Name=$Name;KeyExisted=$false;Existed=$false;Kind=$null;Value=$null}}
    $key=Get-Item -LiteralPath $Path -ErrorAction Stop
    $exists=@($key.GetValueNames()) -contains $Name
    return [pscustomobject]@{Path=$Path;Name=$Name;KeyExisted=$true;Existed=$exists;Kind=$(if($exists){$key.GetValueKind($Name).ToString()}else{$null});Value=$(if($exists){$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}else{$null})}
}
function Set-BnqqRegistrySnapshot {
    param($Snapshot)
    if($Snapshot.Existed){
        [void](New-Item -Path $Snapshot.Path -Force -ErrorAction Stop)
        $v=$Snapshot.Value
        if($Snapshot.Kind -eq 'Binary'){$v=[byte[]]@($v)}
        if($Snapshot.Kind -eq 'MultiString'){$v=[string[]]@($v)}
        [void](New-ItemProperty -LiteralPath $Snapshot.Path -Name $Snapshot.Name -Value $v -PropertyType $Snapshot.Kind -Force -ErrorAction Stop)
    } elseif(Test-Path -LiteralPath $Snapshot.Path -ErrorAction Stop) {
        $key=Get-Item -LiteralPath $Snapshot.Path -ErrorAction Stop
        if(@($key.GetValueNames()) -contains $Snapshot.Name){Remove-ItemProperty -LiteralPath $Snapshot.Path -Name $Snapshot.Name -ErrorAction Stop}
        # Delete only an empty leaf created by BNQQ, never a parent tree.
        if(-not $Snapshot.KeyExisted){
            $key=Get-Item -LiteralPath $Snapshot.Path -ErrorAction Stop
            if($key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0){Remove-Item -LiteralPath $Snapshot.Path -ErrorAction Stop}
        }
    }
}
function Test-BnqqSameValue { param($A,$B); return (($A|ConvertTo-Json -Compress -Depth 15) -ceq ($B|ConvertTo-Json -Compress -Depth 15)) }
function Test-BnqqPartialState {
    param($Op,$Actual)
    if(-not $Actual){return $false}
    if($Op.Kind -eq 'Registry'){
        return (-not $Op.Before.Existed -and -not $Actual.Existed -and $Actual.Path -eq $Op.Before.Path -and $Actual.Name -eq $Op.Before.Name)
    }
    $fields=if($Op.Kind -eq 'Power'){@('AC','DC')}elseif($Op.Kind -eq 'Process'){@('Priority','Affinity')}else{@()}
    if(-not $fields.Count){return $false}
    $candidate=$Actual|Select-Object *
    foreach($field in $fields){
        if(-not (Test-BnqqSameValue $Actual.$field $Op.Before.$field) -and -not (Test-BnqqSameValue $Actual.$field $Op.After.$field)){return $false}
        $candidate.$field=$Op.Before.$field
    }
    return (Test-BnqqSameValue $candidate $Op.Before)
}
function New-BnqqJournal {
    param([string]$Purpose)
    $id=[guid]::NewGuid().ToString('N')
    $j=[pscustomobject]@{Schema=2;Id=$id;Owner=(Get-BnqqOwner);Created=[datetime]::UtcNow.ToString('o');Purpose=$Purpose;Status='Open';Entries=@()}
    $file=Join-Path (Get-BnqqDataRoot) ('journals\'+$id+'.json')
    Write-BnqqAtomicJson $j $file
    return [pscustomobject]@{File=$file;Data=$j}
}
function Assert-BnqqOperation {
    param($Op)
    switch($Op.Kind){
        'Registry' {
            $target=@(Get-BnqqRegistryTargets | Where-Object {$_.Path -ieq $Op.Before.Path -and $_.Name -ceq $Op.Before.Name})
            if($target.Count -ne 1 -or $Op.After.Path -ine $Op.Before.Path -or $Op.After.Name -cne $Op.Before.Name){throw 'Alvo de registro fora da lista auditada'}
            if(@('DWord','QWord','String','ExpandString','MultiString','Binary') -notcontains $Op.Before.Kind -and $Op.Before.Existed){throw 'Tipo de registro invalido'}
            if($Op.After.Kind -ne 'DWord' -or $Op.After.Value -ne 0 -or -not $Op.After.Existed){throw 'Destino de registro invalido'}
        }
        'Power' {
            if($Op.Before.Scheme -notmatch '^[0-9a-fA-F-]{36}$' -or $Op.Before.Setting -ne 'IDLEDISABLE' -or $Op.Before.Sub -ne 'SUB_PROCESSOR' -or $Op.After.Scheme -ne $Op.Before.Scheme -or $Op.After.Setting -ne $Op.Before.Setting -or $Op.After.Sub -ne $Op.Before.Sub){throw 'Operacao de energia invalida'}
            foreach($v in @($Op.Before.AC,$Op.Before.DC,$Op.After.AC,$Op.After.DC)){if($v -notin @(0,1)){throw 'Indice de energia invalido'}}
        }
        'Process' {
            if($Op.Before.Name -notin @('cs2','VALORANT-Win64-Shipping') -or $Op.Before.ProcessId -le 0 -or $Op.After.ProcessId -ne $Op.Before.ProcessId -or $Op.After.StartTime -ne $Op.Before.StartTime -or $Op.After.Name -ne $Op.Before.Name){throw 'Identidade de processo invalida'}
            if($Op.Before.Priority -notin @('Idle','BelowNormal','Normal','AboveNormal','High') -or $Op.After.Priority -notin @('Normal','AboveNormal')){throw 'Prioridade fora da politica'}
            if([int64]$Op.Before.Affinity -le 0 -or [int64]$Op.After.Affinity -le 0){throw 'Mascara invalida'}
        }
        'Shortcut' {
            Assert-BnqqShortcutPath $Op.Before.Path
            if($Op.After.Path -cne $Op.Before.Path -or $Op.After.Target -cne $Op.Before.Target){throw 'Identidade do atalho divergiu'}
            if($Op.After.Arguments -cne (Remove-BnqqBadFlags $Op.Before.Arguments)){throw 'Destino do atalho nao corresponde a limpeza auditada'}
        }
        default {throw 'Tipo de operacao nao auditado'}
    }
}
function Get-BnqqPowerSnapshot {
    param([string]$Scheme)
    if(-not $Scheme){
        $raw=(& powercfg.exe /getactivescheme) -join ' '
        if($LASTEXITCODE -ne 0){throw 'Falha ao consultar plano'}
        $Scheme=[regex]::Match($raw,'[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}').Value
    }
    if(-not $Scheme){throw 'Plano desconhecido'}
    $raw=(& powercfg.exe /qh $Scheme SUB_PROCESSOR IDLEDISABLE) -join ' '
    if($LASTEXITCODE -ne 0){throw 'IDLEDISABLE nao exposto'}
    $hex=[regex]::Matches($raw,'0x([0-9a-fA-F]+)')
    if($hex.Count -lt 2){throw 'Indices de energia desconhecidos'}
    return [pscustomobject]@{Scheme=$Scheme;Sub='SUB_PROCESSOR';Setting='IDLEDISABLE';AC=[Convert]::ToInt32($hex[$hex.Count-2].Groups[1].Value,16);DC=[Convert]::ToInt32($hex[$hex.Count-1].Groups[1].Value,16)}
}
function Get-BnqqProcessSnapshot {
    param([int]$ProcessId)
    $p=Get-Process -Id $ProcessId -ErrorAction Stop
    return [pscustomobject]@{ProcessId=$p.Id;Name=$p.ProcessName;StartTime=$p.StartTime.ToUniversalTime().ToString('o');Priority=$p.PriorityClass.ToString();Affinity=([int64]$p.ProcessorAffinity).ToString()}
}
function Get-BnqqOperationState {
    param($Op)
    switch($Op.Kind){
        'Registry' {Get-RegSnapshot $Op.Before.Path $Op.Before.Name}
        'Shortcut' {Get-BnqqShortcutSnapshot $Op.Before.Path}
        'Power' {Get-BnqqPowerSnapshot $Op.Before.Scheme}
        'Process' {
            $p=Get-Process -Id $Op.Before.ProcessId -ErrorAction SilentlyContinue
            if(-not $p){return $null}
            if($p.StartTime.ToUniversalTime().ToString('o') -ne $Op.Before.StartTime){return $null}
            Get-BnqqProcessSnapshot $p.Id
        }
    }
}
function Set-BnqqOperationState {
    param($Op,$State)
    Assert-BnqqOperation $Op
    switch($Op.Kind){
        'Registry' {Set-BnqqRegistrySnapshot $State}
        'Shortcut' {Set-BnqqShortcutSnapshot $State}
        'Power' {
            $current=Get-BnqqPowerSnapshot $State.Scheme
            $changed=$false
            foreach($mode in @('AC','DC')){
                if($current.$mode -eq $State.$mode){continue}
                $flag=if($mode -eq 'AC'){'/setacvalueindex'}else{'/setdcvalueindex'}
                & powercfg.exe $flag $State.Scheme $State.Sub $State.Setting $State.$mode | Out-Null
                if($LASTEXITCODE -ne 0){throw "Falha ao gravar energia $mode"}
                $changed=$true
            }
            # Do not activate a plan the user has since left.
            $activeText=(& powercfg.exe /getactivescheme) -join ' '
            if($LASTEXITCODE -ne 0){throw 'Plano ativo indeterminado'}
            if($changed -and $activeText -match [regex]::Escape($State.Scheme)){& powercfg.exe /setactive $State.Scheme | Out-Null; if($LASTEXITCODE -ne 0){throw 'Falha ao atualizar plano ativo'}}
        }
        'Process' {
            $live=Get-BnqqOperationState $Op
            if(-not $live){return}
            $p=Get-Process -Id $State.ProcessId -ErrorAction Stop
            $p.PriorityClass=$State.Priority
            $p.ProcessorAffinity=[IntPtr][int64]$State.Affinity
        }
    }
}
function Invoke-BnqqJournalOperation {
    param($Journal,$Operation)
    Assert-BnqqOperation $Operation
    if(-not (Test-BnqqSameValue (Get-BnqqOperationState $Operation) $Operation.Before)){throw 'Alvo mudou desde a captura; nenhuma escrita iniciada'}
    $Operation | Add-Member -NotePropertyName Status -NotePropertyValue 'Prepared' -Force
    $Journal.Data.Entries=@($Journal.Data.Entries)+@($Operation)
    # Write-ahead: if this fails, the target is never changed.
    Write-BnqqAtomicJson $Journal.Data $Journal.File
    try {
        Set-BnqqOperationState $Operation $Operation.After
        $actual=Get-BnqqOperationState $Operation
        if(-not (Test-BnqqSameValue $actual $Operation.After)){throw 'Leitura posterior divergiu do destino'}
        $Operation.Status='Applied'
        Write-BnqqAtomicJson $Journal.Data $Journal.File
    } catch {
        $Operation.Status='Failed'; $Journal.Data.Status='NeedsRecovery'
        Write-BnqqAtomicJson $Journal.Data $Journal.File
        throw
    }
}
function Restore-BnqqJournal {
    param([Parameter(Mandatory)][string]$File)
    $j=Get-Content -LiteralPath $File -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    if($j.Schema -ne 2 -or $j.Owner -ne (Get-BnqqOwner)){throw 'Journal legado/invalido ou de outro usuario; nao ha restauracao presumida'}
    foreach($op in @($j.Entries)){Assert-BnqqOperation $op}
    $errors=@()
    for($i=@($j.Entries).Count-1;$i -ge 0;$i--){
        $op=$j.Entries[$i]
        if($op.Status -in @('Restored','Exited')){continue}
        try {
            $actual=Get-BnqqOperationState $op
            if($op.Kind -eq 'Process' -and -not $actual){$op.Status='Exited'}
            elseif(Test-BnqqSameValue $actual $op.Before){$op.Status='Restored'}
            else {
                # Failed/prepared operations can be partial; applied operations must still match.
                if(-not (Test-BnqqSameValue $actual $op.After) -and -not ($op.Status -in @('Prepared','Failed') -and (Test-BnqqPartialState $op $actual))){throw 'Conflito: alvo alterado fora desta sessao'}
                Set-BnqqOperationState $op $op.Before
                if(-not (Test-BnqqSameValue (Get-BnqqOperationState $op) $op.Before)){throw 'Restauracao nao verificada'}
                $op.Status='Restored'
            }
        } catch {$errors+= $_.Exception.Message}
        Write-BnqqAtomicJson $j $File
    }
    $j.Status=if($errors.Count){'NeedsRecovery'}else{'Restored'}
    Write-BnqqAtomicJson $j $File
    if($errors.Count){throw ($errors -join '; ')}
    return $j
}
function Assert-BnqqNoPendingJournal {
    $dir=Join-Path (Get-BnqqDataRoot) 'journals'
    foreach($f in @(Get-ChildItem $dir -Filter '*.json' -ErrorAction SilentlyContinue)){
        $j=Get-Content $f.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
        if($j.Status -ne 'Restored'){throw ('Restaurar sessao pendente antes de novo experimento: '+$f.FullName)}
    }
}
