[CmdletBinding()]
param(
    [switch]$PinPhysical,
    [int]$IntervalSeconds = 2,
    [switch]$RespectBattery,
    [switch]$DeepFreeze,
    [double]$StandbyThresholdGB = 4,
    [switch]$Once
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:BnqqRoot = $root

. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\Gpu.ps1')
. (Join-Path $root 'lib\Timer.ps1')
. (Join-Path $root 'lib\MemoryGuard.ps1')
. (Join-Path $root 'lib\DiscordRpc.ps1')
. (Join-Path $root 'lib\DeepFreeze.ps1')
. (Join-Path $root 'lib\RuntimeLatency.ps1')
. (Join-Path $root 'lib\ProcessLasso.ps1')
. (Join-Path $root 'lib\Watcher.ps1')

try { Initialize-BnqqProcessLasso | Out-Null } catch { Write-Bnqq ('Process Lasso: preload falhou - {0}' -f $_.Exception.Message) 'WARN' }

Start-BnqqLog -Directory (Join-Path $root 'reports') | Out-Null
Start-BnqqWatcher -IntervalSeconds $IntervalSeconds -PinPhysical:$PinPhysical -RespectBattery:$RespectBattery -DeepFreeze:$DeepFreeze -StandbyThresholdGB $StandbyThresholdGB -Once:$Once
