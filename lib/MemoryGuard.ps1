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
    if (-not (Test-BnqqAdmin)) {
        Write-Bnqq 'Standby purge exige elevacao' 'WARN'
        return $false
    }

    [void](Enable-BnqqPrivilege -Name 'SeProfileSingleProcessPrivilege')

    $command = 4
    $status = [Bnqq.MemoryNative]::NtSetSystemInformation(80, [ref]$command, 4)
    if ($status -eq 0) {
        Write-Bnqq 'Standby list purgada via NtSetSystemInformation' 'OK'
        return $true
    }

    Write-Bnqq ('Standby purge falhou: 0x{0:X8}' -f $status) 'WARN'
    return $false
}

function Get-BnqqFreeMemoryGB {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (-not $os) { return $null }
    return [math]::Round($os.FreePhysicalMemory / 1MB, 2)
}
