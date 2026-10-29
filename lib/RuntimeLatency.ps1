if (-not ('Bnqq.RuntimeNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Bnqq {
    public static class RuntimeNative {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetProcessWorkingSetSize(IntPtr process, out IntPtr minimum, out IntPtr maximum);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetProcessWorkingSetSize(IntPtr process, IntPtr minimum, IntPtr maximum);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(uint access, bool inheritHandle, int processId);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr handle);
    }
}
'@
}

function Get-BnqqForegroundPid {
    $hwnd = [Bnqq.RuntimeNative]::GetForegroundWindow()
    if ($hwnd -eq [IntPtr]::Zero) { return $null }
    $pidValue = [uint32]0
    [Bnqq.RuntimeNative]::GetWindowThreadProcessId($hwnd, [ref]$pidValue) | Out-Null
    if ($pidValue -gt 0) { return [int]$pidValue }
    return $null
}

function Set-BnqqWorkingSetPadding {
    param(
        [Parameter(Mandatory = $true)]$Process,
        [int64]$ExtraMB = 192
    )

    $freeGB = Get-BnqqFreeMemoryGB
    if ($null -ne $freeGB -and $freeGB -lt 2) {
        Write-Bnqq 'Working set: ignorado, RAM livre abaixo de 2 GB' 'WARN'
        return $null
    }

    try {
        $live = Get-Process -Id $Process.Id -ErrorAction Stop
        $name = if ($live.ProcessName) { $live.ProcessName } else { ('PID ' + $live.Id) }
        $handle = [Bnqq.RuntimeNative]::OpenProcess(0x0100 -bor 0x0400, $false, $live.Id)
        if ($handle -eq [IntPtr]::Zero) {
            Write-Bnqq ('Working set: OpenProcess recusado para {0}' -f $name) 'WARN'
            return $null
        }

        try {
            $originalMin = [IntPtr]::Zero
            $originalMax = [IntPtr]::Zero
            if (-not [Bnqq.RuntimeNative]::GetProcessWorkingSetSize($handle, [ref]$originalMin, [ref]$originalMax)) {
                Write-Bnqq ('Working set: GetProcessWorkingSetSize falhou para {0}' -f $name) 'WARN'
                return $null
            }

            $current = [int64]$live.WorkingSet64
            $targetMin = [int64][math]::Max($originalMin.ToInt64(), $current + ($ExtraMB * 1MB))
            $targetMax = [int64][math]::Max($originalMax.ToInt64(), $targetMin + (256MB))

            if (-not [Bnqq.RuntimeNative]::SetProcessWorkingSetSize($handle, [IntPtr]$targetMin, [IntPtr]$targetMax)) {
                Write-Bnqq ('Working set: SetProcessWorkingSetSize recusado para {0}' -f $name) 'WARN'
                return $null
            }

            Write-Bnqq ('Working set: {0} min {1:N0} MB / max {2:N0} MB' -f $name, ($targetMin / 1MB), ($targetMax / 1MB)) 'OK'
            return [pscustomobject]@{
                ProcessId = $live.Id
                ProcessName = $name
                OriginalMin = $originalMin.ToInt64()
                OriginalMax = $originalMax.ToInt64()
                TargetMin = $targetMin
                TargetMax = $targetMax
            }
        }
        finally {
            [Bnqq.RuntimeNative]::CloseHandle($handle) | Out-Null
        }
    }
    catch {
        Write-Bnqq ('Working set indisponivel: {0}' -f $_.Exception.Message) 'WARN'
        return $null
    }
}

function Restore-BnqqWorkingSet {
    param($State)

    if (-not $State) { return }
    $proc = Get-Process -Id $State.ProcessId -ErrorAction SilentlyContinue
    if (-not $proc) { return }
    try {
        $handle = [Bnqq.RuntimeNative]::OpenProcess(0x0100 -bor 0x0400, $false, $proc.Id)
        if ($handle -ne [IntPtr]::Zero) {
            try {
                [Bnqq.RuntimeNative]::SetProcessWorkingSetSize($handle, [IntPtr]$State.OriginalMin, [IntPtr]$State.OriginalMax) | Out-Null
                Write-Bnqq ('Working set restaurado: {0}' -f $State.ProcessName) 'OK'
            }
            finally {
                [Bnqq.RuntimeNative]::CloseHandle($handle) | Out-Null
            }
        }
    }
    catch { }
}

function Set-BnqqRuntimeQos {
    param([Parameter(Mandatory = $true)]$Process)

    $live = Get-Process -Id $Process.Id -ErrorAction SilentlyContinue
    if (-not $live) { return $false }
    $name = if ($live.ProcessName) { $live.ProcessName } else { 'PID ' + $live.Id }
    $path = $live.Path
    if (-not $path) { $path = $name + '.exe' }

    $policyName = 'BNQQ-Runtime-' + $name
    try {
        $existing = @(Get-NetQosPolicy -Name $policyName -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
        if ($existing.Count -eq 0) {
            New-NetQosPolicy -Name $policyName -AppPathNameMatchCondition $path -DSCPAction 46 -PolicyStore ActiveStore -Precedence 1 -ErrorAction Stop | Out-Null
            Write-Bnqq ('QoS runtime: DSCP 46 para {0}' -f $name) 'OK'
        }
        else {
            Write-Bnqq ('QoS runtime: politica ja ativa para {0}' -f $name) 'INFO'
        }
        return $true
    }
    catch {
        Write-Bnqq ('QoS runtime indisponivel: {0}' -f $_.Exception.Message) 'WARN'
        return $false
    }
}

function Set-BnqqGameProcessPriority {
    param([Parameter(Mandatory = $true)]$Process)

    try {
        if ($Process.PriorityClass -ne [System.Diagnostics.ProcessPriorityClass]::High) {
            $Process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
            Write-Bnqq ('Prioridade runtime: {0} -> High' -f $Process.ProcessName) 'OK'
        }
    }
    catch {
        Write-Bnqq ('Prioridade runtime recusada: {0}' -f $Process.ProcessName) 'WARN'
    }
}

function Get-BnqqGameRuntimeProfile {
    param([Parameter(Mandatory = $true)]$Process)

    $name = $Process.ProcessName
    if ($name -eq 'cs2') {
        return [pscustomobject]@{ Game = 'CS2'; WorkingSetExtraMB = 192; Dscp = 46 }
    }
    if ($name -eq 'VALORANT-Win64-Shipping') {
        return [pscustomobject]@{ Game = 'Valorant'; WorkingSetExtraMB = 256; Dscp = 46 }
    }
    return [pscustomobject]@{ Game = $name; WorkingSetExtraMB = 128; Dscp = 46 }
}

function Set-BnqqRuntimeLatency {
    param(
        [Parameter(Mandatory = $true)]$Process,
        [int64]$ExtraMB = 192
    )

    $qos = Set-BnqqRuntimeQos -Process $Process
    $workingSet = Set-BnqqWorkingSetPadding -Process $Process -ExtraMB $ExtraMB
    try {
        if ((Get-BnqqFreeMemoryGB) -lt 4) {
            if (Clear-BnqqStandbyList) { Write-Bnqq 'Runtime: standby list purgada no foco do jogo' 'OK' }
        }
    }
    catch { }

    return [pscustomobject]@{
        ProcessId = $Process.Id
        ProcessName = $Process.ProcessName
        QoS = $qos
        WorkingSet = $workingSet
    }
}
