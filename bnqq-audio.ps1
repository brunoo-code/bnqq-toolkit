[CmdletBinding()]
param(
    [int]$Core = 5,
    [int]$IntervalSeconds = 5
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:BnqqRoot = $root

. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\Audio.ps1')

Start-BnqqLog -Directory (Join-Path $root 'reports') | Out-Null

$lastState = $null
$lastError = $null

while ($true) {
    $result = Set-BnqqAudiodgAffinity -Core $Core -Quiet
    $state = if (-not $result.Running) { 'ausente' } elseif ($result.Ok) { 'ok' } else { 'falha' }

    if ($state -ne $lastState) {
        if ($state -eq 'ok') {
            Write-Bnqq ('Audio: audiodg isolado no CPU logico {0} com prioridade High' -f $Core) 'OK'
        }
        elseif ($state -eq 'falha') {
            Write-Bnqq ('Audio: nao foi possivel isolar audiodg: {0}' -f $result.Error) 'WARN'
        }
        $lastState = $state
        $lastError = $result.Error
    }
    elseif ($state -eq 'falha' -and $result.Error -ne $lastError) {
        Write-Bnqq ('Audio: erro atualizado: {0}' -f $result.Error) 'WARN'
        $lastError = $result.Error
    }

    Start-Sleep -Seconds $IntervalSeconds
}
