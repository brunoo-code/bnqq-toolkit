function Set-BnqqIoQueueDepth {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\I/O System'
    Set-BnqqReg $base 'AdditionalCriticalWorkerThreads' 8
    Set-BnqqReg $base 'AdditionalDelayedWorkerThreads' 4
    Write-Bnqq 'I/O: 8 worker threads criticos + 4 delayed para fila assincrona' 'OK'
}

function Invoke-BnqqSsdTrim {
    $done = 0

    $volumes = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object {
        $_.DriveType -eq 'Fixed' -and $_.FileSystem -eq 'NTFS' -and $_.DriveLetter
    })

    foreach ($vol in $volumes) {
        try {
            $part = Get-Partition -DriveLetter $vol.DriveLetter -ErrorAction Stop
            $disk = Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceID -eq $part.DiskNumber } | Select-Object -First 1
            if (-not $disk -or $disk.MediaType -ne 'SSD') { continue }
        }
        catch { continue }

        $sw = [Diagnostics.Stopwatch]::StartNew()
        Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -ErrorAction SilentlyContinue
        $sw.Stop()

        Write-Bnqq ('TRIM {0}: concluido em {1:N1}s' -f $vol.DriveLetter, $sw.Elapsed.TotalSeconds) 'OK'
        $done++
    }

    if ($done -eq 0) { Write-Bnqq 'Nenhum SSD NTFS elegivel para TRIM' 'INFO' }
}
