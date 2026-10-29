[CmdletBinding()]
param(
    [switch]$PinPhysical,
    [int]$IntervalSeconds = 2,
    [switch]$RespectBattery,
    [double]$StandbyThresholdGB = 4
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:BnqqRoot = $root

. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\Gpu.ps1')
. (Join-Path $root 'lib\Timer.ps1')
. (Join-Path $root 'lib\MemoryGuard.ps1')
. (Join-Path $root 'lib\Watcher.ps1')

Start-BnqqLog -Directory (Join-Path $root 'reports') | Out-Null
Start-BnqqWatcher -IntervalSeconds $IntervalSeconds -PinPhysical:$PinPhysical -RespectBattery:$RespectBattery -StandbyThresholdGB $StandbyThresholdGB
