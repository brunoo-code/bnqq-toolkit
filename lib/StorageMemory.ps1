function Invoke-BnqqSystemVolumeMaintenance {
    if (-not (Test-BnqqAdmin)) { throw 'Manutencao de armazenamento exige administrador.' }
    $letter = $env:SystemDrive.TrimEnd(':')
    Write-Host 'Estado das notificacoes TRIM (0 = habilitadas):'
    & fsutil.exe behavior query DisableDeleteNotify
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Nao foi possivel consultar o TRIM.' }

    $lock = Enter-BnqqStateLock
    try {
        $file = Join-Path (Get-BnqqDataRoot) 'optimizer-storage-last-run.json'
        $now = [DateTimeOffset]::UtcNow
        if (Test-Path -LiteralPath $file) {
            $previous = Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $completed = [DateTimeOffset]$previous.CompletedUtc
            if ($previous.Computer -eq $env:COMPUTERNAME -and $previous.DriveLetter -eq $letter -and
                $completed -le $now -and ($now - $completed).TotalDays -lt 7) {
                Write-Host 'Manutencao ja concluida pelo BNQQ nos ultimos 7 dias.'
                return
            }
        }
        Optimize-Volume -DriveLetter $letter -Verbose -ErrorAction Stop
        Write-BnqqAtomicJson -Value @{
            Computer = $env:COMPUTERNAME
            DriveLetter = $letter
            CompletedUtc = [DateTimeOffset]::UtcNow.ToString('o')
        } -Path $file
    } finally { $lock.Dispose() }
}

function Get-BnqqSystemStorage {
    $letter = $env:SystemDrive.TrimEnd(':')
    $disk = Get-Partition -DriveLetter $letter -ErrorAction Stop | Get-Disk -ErrorAction Stop
    $volume = Get-Volume -DriveLetter $letter -ErrorAction Stop
    $physical = @()
    if ($disk.UniqueId) {
        $physical = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object UniqueId -eq $disk.UniqueId)
    }
    $media = if ($physical.Count -eq 1) { [string]$physical[0].MediaType } else { 'Unknown' }
    $guidance = switch ($media) {
        'SSD' { 'SSD detectado. Considere testar Compact OS se faltar espaco. Compare boot e carregamento.' }
        'HDD' { 'HD mecanico detectado. Compact OS nao recomendado.' }
        default { 'Midia fisica indeterminada. Confirme o disco real antes de avaliar Compact OS.' }
    }
    [pscustomobject]@{
        Volume = $env:SystemDrive
        Disk = $disk.FriendlyName
        Bus = [string]$disk.BusType
        Media = $media
        FreeGiB = [math]::Round($volume.SizeRemaining / 1GB, 2)
        TotalGiB = [math]::Round($volume.Size / 1GB, 2)
        CompactOsGuidance = $guidance
    }
}

function Get-BnqqMemorySnapshot {
    if(-not ('Bnqq.MemoryStatus' -as [type])){Add-Type -Path (Join-Path $script:BnqqRoot 'lib\MemoryStatus.cs') -ErrorAction Stop}
    return [Bnqq.MemoryStatus]::Read()
}
function Get-BnqqMemoryReport {
    $m=Get-BnqqMemorySnapshot
    $headroom=[decimal]$m.CommitLimitBytes-[decimal]$m.CommitUsedBytes
    return [pscustomobject]@{Source='Kernel32.K32GetPerformanceInfo';Snapshot=$m;AvailableGiB=[math]::Round($m.PhysicalAvailableBytes/1GB,2);CommitHeadroomGiB=[math]::Round($headroom/1GB,2);SeverePressure=($m.PhysicalAvailableBytes -lt 512MB -or $headroom -lt 1GB);Action='Preserve';Note='Snapshot, nao diagnostico de stutter. Disponivel inclui standby reutilizavel. Nao limpa RAM, nao altera paginação nem concede Lock Pages: a aplicacao precisa alocar Large Pages explicitamente.'}
}
function Assert-BnqqMemoryHeadroom {
    if((Get-BnqqMemoryReport).SeverePressure){throw 'Pouca RAM disponivel ou margem de commit; resolva a pressao antes de outro experimento'}
}
function Get-BnqqNvmeSupport {
    $errors=@();$disks=@();$controllers=@();$driver=$null
    try {
        $disks=@(Get-Disk -ErrorAction Stop|Where-Object BusType -eq 'NVMe'|Select-Object Number,FriendlyName,BusType)
        $devices=@(Get-PnpDevice -Class SCSIAdapter -PresentOnly -ErrorAction Stop)
        if($devices.Count -gt 64){throw 'Muitos controladores; suporte indeterminado'}
        foreach($d in $devices){
            $service=Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName DEVPKEY_Device_Service -ErrorAction Stop
            if($service.Data -ieq 'stornvme'){$controllers+=@([pscustomobject]@{Instance=$d.InstanceId;Service='stornvme'})}
        }
        $driver=Get-CimInstance Win32_SystemDriver -Filter "Name='stornvme'" -OperationTimeoutSec 5 -ErrorAction Stop
    }catch{$errors+=$_.Exception.Message}
    return [pscustomobject]@{Supported=($errors.Count -eq 0 -and $disks.Count -gt 0 -and $controllers.Count -gt 0 -and $driver.State -eq 'Running');Disks=$disks;Controllers=$controllers;Errors=$errors;Scope='Politica do plano para controladores Microsoft StorNVMe; nao altera firmware, MSI ou buffers NTFS'}
}
function Get-BnqqNvmePlan {
    $support=Get-BnqqNvmeSupport
    if(-not $support.Supported){return [pscustomobject]@{Status='Unsupported';Support=$support;Operations=@()}}
    $ops=@();$snapshots=@()
    foreach($id in @('fc95af4d-40e7-4b6d-835a-56d131dbc80e','dbc9e238-6de9-49e3-92cd-8c2b4946b472')){
        $before=Get-BnqqPowerSnapshot -Setting $id;$snapshots+=@($before)
        if($before.AC -ne 0){$after=$before|Select-Object *;$after.AC=0;$ops+=@([pscustomobject]@{Kind='Power';Before=$before;After=$after})}
    }
    if(@($snapshots|Select-Object -ExpandProperty Scheme -Unique).Count -ne 1){throw 'Plano mudou durante a captura NVMe'}
    return [pscustomobject]@{Status=$(if($ops.Count){'Candidate'}else{'AlreadyConfigured'});Support=$support;Before=$snapshots;Operations=$ops;Note='Orcamento de latencia de transicao AC=0 ms, DC preservado. Nao mede estado fisico do SSD, IO por frame ou ganho de FPS. Pode elevar consumo/temperatura.'}
}
function Invoke-BnqqNvmePolicy {
    param([ValidateSet('plan','apply','restore')][string]$Action='plan',[string]$File)
    if($Action -eq 'plan'){return (Get-BnqqNvmePlan)}
    if($Action -eq 'restore'){return (Invoke-BnqqRecovery $File)}
    $lock=Enter-BnqqStateLock
    try {
        Assert-BnqqNoPendingJournal
        $plan=Get-BnqqNvmePlan
        if(-not @($plan.Operations).Count){return $plan}
        Assert-BnqqHeavyQa;Assert-BnqqMemoryHeadroom
        if(-not (Test-BnqqAdmin)){throw 'Politica NVMe exige administrador'}
        $j=New-BnqqJournal 'nvme-latency-budget-v2-phase3'
        try {
            foreach($op in @($plan.Operations)){
                if((Get-BnqqPowerSnapshot -Setting $op.Before.Setting).Scheme -cne $op.Before.Scheme){throw 'Plano ativo mudou; cancelar experimento NVMe'}
                Invoke-BnqqJournalOperation $j $op;Assert-BnqqPhaseHealth ([datetime]::Parse($j.Data.Created))
            }
            $j.Data.Status='Applied';Write-BnqqAtomicJson $j.Data $j.File
            return [pscustomobject]@{Status='Applied';Journal=$j.File;PerformanceMeasured=$false}
        }catch{
            $original=$_;$original.Exception.Data['BnqqJournal']=$j.File;Write-BnqqNightLog 'NVME-FAILED' $original.Exception.Message
            try{Restore-BnqqJournal $j.File|Out-Null}catch{$_.Exception.Data['BnqqJournal']=$j.File;throw}
            throw $original
        }
    }finally{$lock.Dispose()}
}
function Show-BnqqStorageMenu {
    Get-BnqqMemoryReport|Format-List
    $plan=Invoke-BnqqNvmePolicy
    $plan|Format-List
    if(@($plan.Operations).Count -and (Read-Host 'Aplicar orcamento NVMe AC=0 ms? Nao significa latencia real zero. Digite NVME') -ceq 'NVME'){
        Invoke-BnqqNvmePolicy -Action apply|Format-List
    }
}
