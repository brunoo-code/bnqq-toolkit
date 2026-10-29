if (-not ('Bnqq.MemoryNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Bnqq {
    public static class MemoryNative {
        [StructLayout(LayoutKind.Sequential)]
        public struct LUID {
            public uint LowPart;
            public int HighPart;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct LUID_AND_ATTRIBUTES {
            public LUID Luid;
            public uint Attributes;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct TOKEN_PRIVILEGES {
            public int PrivilegeCount;
            public LUID_AND_ATTRIBUTES Privileges;
        }

        [DllImport("ntdll.dll")]
        public static extern int NtSetSystemInformation(int systemInformationClass, ref int systemInformation, int systemInformationLength);

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern bool OpenProcessToken(IntPtr processHandle, uint desiredAccess, out IntPtr tokenHandle);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool LookupPrivilegeValue(string systemName, string name, out LUID luid);

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern bool AdjustTokenPrivileges(IntPtr tokenHandle, bool disableAllPrivileges, ref TOKEN_PRIVILEGES newState, int bufferLength, IntPtr previousState, IntPtr returnLength);

        [DllImport("kernel32.dll")]
        public static extern IntPtr GetCurrentProcess();

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr handle);

        public static bool EnablePrivilege(string name) {
            IntPtr token = IntPtr.Zero;
            if (!OpenProcessToken(GetCurrentProcess(), 0x28, out token)) return false;
            try {
                LUID luid;
                if (!LookupPrivilegeValue(null, name, out luid)) return false;
                TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
                tp.PrivilegeCount = 1;
                tp.Privileges.Luid = luid;
                tp.Privileges.Attributes = 0x2;
                return AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
            }
            finally {
                CloseHandle(token);
            }
        }
    }
}
'@
}

function Enable-BnqqPrivilege {
    param([string]$Name)
    return [Bnqq.MemoryNative]::EnablePrivilege($Name)
}

function Clear-BnqqStandbyList {
    param([switch]$Quiet)

    if (-not (Test-BnqqAdmin)) {
        if (-not $Quiet) { Write-Bnqq 'Standby purge exige elevacao' 'WARN' }
        return $false
    }

    [void](Enable-BnqqPrivilege -Name 'SeProfileSingleProcessPrivilege')

    $beforeGB = Get-BnqqFreeMemoryGB
    $command = 4
    $status = [Bnqq.MemoryNative]::NtSetSystemInformation(80, [ref]$command, 4)
    if ($status -eq 0) {
        if (-not $Quiet) {
            $afterGB = Get-BnqqFreeMemoryGB
            if ($null -ne $beforeGB -and $null -ne $afterGB) {
                Write-Bnqq ('Standby list purgada via NtSetSystemInformation ({0:N2} GB -> {1:N2} GB livres)' -f $beforeGB, $afterGB) 'OK'
            }
            else {
                Write-Bnqq 'Standby list purgada via NtSetSystemInformation' 'OK'
            }
        }
        return $true
    }

    if (-not $Quiet) { Write-Bnqq ('Standby purge falhou: 0x{0:X8}' -f $status) 'WARN' }
    return $false
}

function Get-BnqqFreeMemoryGB {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (-not $os) { return $null }
    return [math]::Round($os.FreePhysicalMemory / 1MB, 2)
}

function Get-BnqqMemoryTuneStatus {
    $mm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    $paging = (Get-ItemProperty -LiteralPath $mm -Name DisablePagingExecutive -ErrorAction SilentlyContinue).DisablePagingExecutive
    $compression = $null
    $compressionError = $null
    try {
        $agent = Get-MMAgent -ErrorAction Stop
        $compression = [bool]$agent.MemoryCompression
    }
    catch {
        $compressionError = $_.Exception.Message
    }

    $standbyGB = $null
    $availableMB = $null
    try {
        $perf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop
        $availableMB = [int]$perf.AvailableMBytes
        if ($null -ne $perf.StandbyCacheNormalPriorityBytes) {
            $standbyGB = [math]::Round($perf.StandbyCacheNormalPriorityBytes / 1GB, 2)
        }
    }
    catch { }

    $freeGB = Get-BnqqFreeMemoryGB
    $allOk = ($paging -eq 1) -and ($compression -eq $false)
    return [pscustomobject]@{
        MemoryCompression = $compression
        MemoryCompressionError = $compressionError
        DisablePagingExecutive = $paging
        FreeGB = $freeGB
        AvailableMB = $availableMB
        StandbyGB = $standbyGB
        AllOk = $allOk
        RebootRequired = (($paging -ne 1) -or ($compression -eq $true))
    }
}

function Set-BnqqMemoryTune {
    param(
        [switch]$Remove,
        [switch]$Purge
    )

    if (-not (Test-BnqqAdmin)) { throw 'Memoria: exige elevacao para alterar o kernel' }

    $mm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    if ($Remove) {
        try {
            Enable-MMAgent -MemoryCompression -ErrorAction Stop
            Write-Bnqq 'Memory Compression: ativado' 'OK'
        }
        catch {
            Write-Bnqq ('Memory Compression: falha ao reativar - {0}' -f $_.Exception.Message) 'WARN'
        }
        Set-BnqqReg $mm 'DisablePagingExecutive' 0 'DWord'
        Write-Bnqq 'Kernel: paging executive restaurado ao padrao (reboot)' 'OK'
        return
    }

    try {
        Disable-MMAgent -MemoryCompression -ErrorAction Stop
        Write-Bnqq 'Memory Compression: desativado' 'OK'
    }
    catch {
        Write-Bnqq ('Memory Compression: falha ao desativar - {0}' -f $_.Exception.Message) 'WARN'
    }

    Set-BnqqReg $mm 'DisablePagingExecutive' 1 'DWord'
    Write-Bnqq 'Kernel: DisablePagingExecutive=1 (reboot para valer)' 'OK'

    if ($Purge) {
        if (Clear-BnqqStandbyList) { Write-Bnqq 'Standby list: limpeza inicial concluida' 'OK' }
    }
}

function Show-BnqqMemoryTuneStatus {
    param($Status)

    if (-not $Status) { $Status = Get-BnqqMemoryTuneStatus }

    Write-Host ''
    Write-Host '  MEMORIA / KERNEL' -ForegroundColor Cyan
    if ($null -eq $Status.MemoryCompression) {
        Write-Host ('    Memory Compression      indeterminado ({0})' -f $Status.MemoryCompressionError) -ForegroundColor Yellow
    }
    else {
        $compColor = if ($Status.MemoryCompression) { 'Yellow' } else { 'Green' }
        Write-Host ('    Memory Compression      {0}' -f $(if ($Status.MemoryCompression) { 'ativo' } else { 'desativado' })) -ForegroundColor $compColor
    }

    $pagingColor = if ($Status.DisablePagingExecutive -eq 1) { 'Green' } else { 'Yellow' }
    Write-Host ('    DisablePagingExecutive  {0}  [{1}]' -f $Status.DisablePagingExecutive, $(if ($Status.DisablePagingExecutive -eq 1) { 'OK - kernel em RAM' } else { 'padrao' })) -ForegroundColor $pagingColor
    Write-Host ('    RAM livre               {0} GB' -f $Status.FreeGB) -ForegroundColor Gray
    Write-Host ('    Standby list            {0} GB' -f $Status.StandbyGB) -ForegroundColor Gray
    Write-Host ('    Disponivel              {0} MB' -f $Status.AvailableMB) -ForegroundColor Gray
    $state = if ($Status.AllOk) { 'OTIMIZADO' } elseif ($null -eq $Status.MemoryCompression) { 'INDETERMINADO (leitura exige elevacao)' } else { 'PENDENTE' }
    Write-Host ('    Estado global           {0}' -f $state) -ForegroundColor $(if ($Status.AllOk) { 'Green' } else { 'Yellow' })
    Write-Host '    Aplicar: .\bnqq.ps1 memtune -MemoryAction apply' -ForegroundColor DarkGray
    Write-Host '    Reverter: .\bnqq.ps1 memtune -MemoryAction remove' -ForegroundColor DarkGray
    Write-Host ''
}
