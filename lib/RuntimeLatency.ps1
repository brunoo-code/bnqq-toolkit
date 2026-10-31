function Initialize-BnqqForeground {
    if('Bnqq.Foreground' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Bnqq { public static class Foreground {
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    public static int Pid(){uint pid; GetWindowThreadProcessId(GetForegroundWindow(),out pid);return (int)pid;}
}}
'@ -ErrorAction Stop
}
function Get-BnqqForegroundPid {Initialize-BnqqForeground; return [Bnqq.Foreground]::Pid()}
function New-BnqqRuntimeOperation {
    param([int]$ProcessId,[switch]$PinPhysical,[switch]$AboveNormal)
    $before=Get-BnqqProcessSnapshot $ProcessId
    $after=$before|Select-Object *
    if($AboveNormal){$after.Priority='AboveNormal'}
    if($PinPhysical){
        $mask=(Get-BnqqSafeGameMask) -band ([int64]$before.Affinity)
        if($mask -eq 0){throw 'Sem intersecao com afinidade atual'}
        $after.Affinity=$mask.ToString()
    }
    return [pscustomobject]@{Kind='Process';Before=$before;After=$after}
}
