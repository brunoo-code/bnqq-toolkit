$script:BnqqTimerState = @{
    Active  = $false
    Desired = [uint32]5000
    Current = $null
}

if (-not ('Bnqq.TimerNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Bnqq {
    public static class TimerNative {
        [DllImport("ntdll.dll")]
        public static extern int NtQueryTimerResolution(out uint minimum, out uint maximum, out uint current);

        [DllImport("ntdll.dll")]
        public static extern int NtSetTimerResolution(uint desired, [MarshalAs(UnmanagedType.U1)] bool set, out uint current);
    }
}
'@
}

function Get-BnqqTimerResolution {
    $minimum = [uint32]0
    $maximum = [uint32]0
    $current = [uint32]0
    $status = [Bnqq.TimerNative]::NtQueryTimerResolution([ref]$minimum, [ref]$maximum, [ref]$current)

    return [pscustomobject]@{
        Status       = $status
        Minimum100ns = $minimum
        Maximum100ns = $maximum
        Current100ns = $current
        MinimumMs    = [math]::Round($minimum / 10000.0, 3)
        MaximumMs    = [math]::Round($maximum / 10000.0, 3)
        CurrentMs    = [math]::Round($current / 10000.0, 3)
        Active       = [bool]$script:BnqqTimerState.Active
        Desired100ns = $script:BnqqTimerState.Desired
    }
}

function Set-BnqqTimerResolution {
    param([uint32]$Desired = 5000)

    if ($script:BnqqTimerState.Active) { return (Get-BnqqTimerResolution) }

    $current = [uint32]0
    $status = [Bnqq.TimerNative]::NtSetTimerResolution($Desired, $true, [ref]$current)
    if ($status -ne 0) {
        Write-Bnqq ('NtSetTimerResolution falhou: 0x{0:X8}' -f $status) 'WARN'
        return $null
    }

    $script:BnqqTimerState.Active = $true
    $script:BnqqTimerState.Desired = $Desired
    $script:BnqqTimerState.Current = $current
    Write-Bnqq ('Timer resolution: {0:N3} ms (solicitado {1:N3} ms)' -f ($current / 10000.0), ($Desired / 10000.0)) 'OK'
    return (Get-BnqqTimerResolution)
}

function Clear-BnqqTimerResolution {
    if (-not $script:BnqqTimerState.Active) { return (Get-BnqqTimerResolution) }

    $current = [uint32]0
    $status = [Bnqq.TimerNative]::NtSetTimerResolution($script:BnqqTimerState.Desired, $false, [ref]$current)
    if ($status -ne 0) {
        Write-Bnqq ('NtSetTimerResolution (clear) falhou: 0x{0:X8}' -f $status) 'WARN'
        return $null
    }

    $script:BnqqTimerState.Active = $false
    Write-Bnqq ('Timer resolution liberado: {0:N3} ms' -f ($current / 10000.0)) 'OK'
    return (Get-BnqqTimerResolution)
}

function Show-BnqqTimerStatus {
    $timer = Get-BnqqTimerResolution
    $color = if ($timer.CurrentMs -le 0.5) { 'Green' } elseif ($timer.CurrentMs -le 1.0) { 'Yellow' } else { 'Gray' }
    $owner = if ($timer.Active) { 'BNQQ ativo' } elseif ($timer.CurrentMs -le 0.5) { '0.5 ms ativo' } else { 'sistema' }
    Write-Host ('  Timer resolution  {0:N3} ms (faixa {1:N3}-{2:N3} ms)  {3}' -f $timer.CurrentMs, $timer.MaximumMs, $timer.MinimumMs, $owner) -ForegroundColor $color
}
