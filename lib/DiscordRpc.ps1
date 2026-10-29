# Discord Rich Presence via local IPC.
# Crie um aplicativo em https://discord.com/developers/applications e cole o Application ID abaixo.
$script:BnqqDiscordClientId = '1565351228672712846'
$script:BnqqDiscordState = $null

function Write-BnqqDiscordFrame {
    param(
        [Parameter(Mandatory = $true)]$Pipe,
        [Parameter(Mandatory = $true)][int]$Opcode,
        [Parameter(Mandatory = $true)][string]$Json
    )

    $payload = [Text.Encoding]::UTF8.GetBytes($Json)
    $header = New-Object byte[] 8
    [BitConverter]::GetBytes([int]$Opcode).CopyTo($header, 0)
    [BitConverter]::GetBytes([int]$payload.Length).CopyTo($header, 4)
    $Pipe.Write($header, 0, $header.Length)
    $Pipe.Write($payload, 0, $payload.Length)
    $Pipe.Flush()
}

function Connect-BnqqDiscordPipe {
    if ([string]::IsNullOrWhiteSpace($script:BnqqDiscordClientId)) { return $null }
    if ($script:BnqqDiscordState -and $script:BnqqDiscordState.Connected) { return $script:BnqqDiscordState }

    try {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'discord-ipc-0', [System.IO.Pipes.PipeDirection]::InOut, [System.IO.Pipes.PipeOptions]::Asynchronous)
        $pipe.Connect(300)
        $handshake = @{ v = 1; client_id = $script:BnqqDiscordClientId } | ConvertTo-Json -Compress
        Write-BnqqDiscordFrame -Pipe $pipe -Opcode 0 -Json $handshake
        $script:BnqqDiscordState = $pipe
        return $pipe
    }
    catch {
        if ($pipe) { try { $pipe.Dispose() } catch { } }
        return $null
    }
}

function Set-BnqqDiscordPresence {
    param([string]$Game = 'BNQQ Toolkit')

    if ([string]::IsNullOrWhiteSpace($script:BnqqDiscordClientId)) {
        Write-Bnqq 'Discord RPC: Application ID nao configurado em lib/DiscordRpc.ps1' 'INFO'
        return $false
    }

    try {
        $pipe = Connect-BnqqDiscordPipe
        if (-not $pipe) {
            Write-Bnqq 'Discord RPC: Discord nao esta ouvindo em discord-ipc-0' 'INFO'
            return $false
        }

        $activity = @{
            details = 'Kernel Environment: BNQQ Toolkit'
            state = 'Hardware P-States Locked'
            timestamps = @{ start = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
        }
        $payload = @{
            cmd = 'SET_ACTIVITY'
            args = @{ pid = $PID; activity = $activity }
            nonce = [guid]::NewGuid().ToString()
        } | ConvertTo-Json -Compress -Depth 6

        Write-BnqqDiscordFrame -Pipe $pipe -Opcode 1 -Json $payload
        Write-Bnqq ('Discord RPC: presenca ativa ({0})' -f $Game) 'OK'
        return $true
    }
    catch {
        Write-Bnqq ('Discord RPC indisponivel: {0}' -f $_.Exception.Message) 'WARN'
        return $false
    }
}

function Clear-BnqqDiscordPresence {
    if (-not $script:BnqqDiscordState) { return }
    try {
        if ($script:BnqqDiscordState.Connected) {
            $payload = @{
                cmd = 'SET_ACTIVITY'
                args = @{ pid = $PID; activity = $null }
                nonce = [guid]::NewGuid().ToString()
            } | ConvertTo-Json -Compress -Depth 6
            Write-BnqqDiscordFrame -Pipe $script:BnqqDiscordState -Opcode 1 -Json $payload
        }
    }
    catch { }
    finally {
        try { $script:BnqqDiscordState.Dispose() } catch { }
        $script:BnqqDiscordState = $null
    }
}