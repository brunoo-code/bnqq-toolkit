if (-not ('Bnqq.FreezeNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Bnqq {
    public static class FreezeNative {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(uint access, bool inheritHandle, int processId);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr handle);

        [DllImport("ntdll.dll")]
        public static extern int NtSuspendProcess(IntPtr process);

        [DllImport("ntdll.dll")]
        public static extern int NtResumeProcess(IntPtr process);
    }
}
'@
}

$script:BnqqFrozenProcesses = @{}
$script:BnqqDeepFreezeExcluded = @(
    'cs2', 'VALORANT-Win64-Shipping', 'vgc', 'vgk', 'Vanguard',
    'RiotClientServices', 'RiotClientCrashHandler', 'RiotClientUx',
    'audiodg', 'dwm', 'winlogon', 'csrss', 'services', 'lsass',
    'System', 'Registry', 'MsMpEng', 'MsMpEngCP', 'SecurityHealthService'
)

function Get-BnqqDeepFreezeCandidates {
    param([switch]$IncludeExplorer)

    $names = @(
        'steamwebhelper', 'steam', 'steamservice',
        'Updater', 'GoogleUpdate', 'MicrosoftEdgeUpdate', 'AdobeUpdateService',
        'Discord', 'chrome', 'msedge', 'msedgewebview2', 'firefox', 'brave',
        'Spotify', 'OneDrive', 'Dropbox', 'EpicGamesLauncher', 'Battle.net',
        'GalaxyClient', 'ArmouryCrate.UserSessionHelper', 'RogLiveService',
        'RazerCentralService', 'LogiOptions'
    )
    if ($IncludeExplorer) { $names += 'explorer' }

    return @(Get-Process -Name $names -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -ne $PID -and $script:BnqqDeepFreezeExcluded -notcontains $_.ProcessName })
}

function Freeze-BnqqBackground {
    param([switch]$IncludeExplorer)

    $count = 0
    foreach ($proc in @(Get-BnqqDeepFreezeCandidates -IncludeExplorer:$IncludeExplorer)) {
        if ($script:BnqqFrozenProcesses.ContainsKey($proc.Id)) { continue }
        $handle = [Bnqq.FreezeNative]::OpenProcess(0x0800, $false, $proc.Id)
        if ($handle -eq [IntPtr]::Zero) { continue }
        try {
            if ([Bnqq.FreezeNative]::NtSuspendProcess($handle) -eq 0) {
                $script:BnqqFrozenProcesses[$proc.Id] = $proc.ProcessName
                $count++
            }
        }
        finally {
            [Bnqq.FreezeNative]::CloseHandle($handle) | Out-Null
        }
    }

    if ($count -gt 0) {
        Write-Bnqq ('Deep Freeze: {0} processo(s) suspenso(s)' -f $count) 'OK'
    }
    return $count
}

function Resume-BnqqBackground {
    $count = 0
    foreach ($id in @($script:BnqqFrozenProcesses.Keys)) {
        $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
        if (-not $proc) {
            $script:BnqqFrozenProcesses.Remove($id)
            continue
        }
        $handle = [Bnqq.FreezeNative]::OpenProcess(0x0800, $false, $id)
        if ($handle -eq [IntPtr]::Zero) { continue }
        try {
            if ([Bnqq.FreezeNative]::NtResumeProcess($handle) -eq 0) {
                $script:BnqqFrozenProcesses.Remove($id)
                $count++
            }
        }
        finally {
            [Bnqq.FreezeNative]::CloseHandle($handle) | Out-Null
        }
    }

    if ($count -gt 0) {
        Write-Bnqq ('Deep Freeze: {0} processo(s) retomado(s)' -f $count) 'OK'
    }
    return $count
}

function Get-BnqqDeepFreezeStatus {
    $candidates = @(Get-BnqqDeepFreezeCandidates | Select-Object Id, ProcessName, WorkingSet64)
    return [pscustomobject]@{
        Frozen = @($script:BnqqFrozenProcesses.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Id = $_.Key; Name = $_.Value } })
        Candidates = $candidates
        Excluded = $script:BnqqDeepFreezeExcluded
        Note = 'Explorer, Riot Client, Vanguard, audio, DWM e processos de seguranca ficam fora por padrao'
    }
}
