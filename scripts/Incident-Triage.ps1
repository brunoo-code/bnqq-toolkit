[CmdletBinding()]
param(
    [ValidateRange(1, 120)][int]$LookbackMinutes = 15,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $OutDir) {
    $OutDir = Join-Path $root 'reports'
}
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}

$os = Get-CimInstance Win32_OperatingSystem
$boot = $os.LastBootUpTime
$from = $boot.AddMinutes(-$LookbackMinutes)
$to = $boot.AddMinutes(5)
$ids = @(41, 1001, 6008, 18, 19, 37, 42, 86, 87, 153, 4231, 2004, 2019, 2020, 5858)

function Get-BnqqIncidentEvents {
    param([datetime]$Start, [datetime]$End)
    try {
        return @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $Start; EndTime = $End } -ErrorAction Stop)
    }
    catch {
        return @()
    }
}

$system = Get-BnqqIncidentEvents -Start $from -End $to
$selected = @($system | Where-Object { $ids -contains $_.Id } | Sort-Object TimeCreated)
$whea = @($selected | Where-Object { $_.ProviderName -match 'WHEA' -and $_.Id -eq 18 })
$power41 = @($selected | Where-Object { $_.ProviderName -match 'Kernel-Power' -and $_.Id -eq 41 })
$thermal = @($selected | Where-Object { $_.Id -in @(86, 87, 37) })
$nvidia = @($selected | Where-Object { $_.ProviderName -match 'nvlddmkm' })
$network = @($selected | Where-Object { $_.Id -eq 4231 })
$wmi = @()
try {
    $wmi = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-WMI-Activity/Operational'; StartTime = $from; EndTime = $to } -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -in @(5858, 5860, 5861) } | Sort-Object TimeCreated)
}
catch { }

$dumps = @()
try {
    $dumps = @(Get-ChildItem 'C:\Windows\Minidump', 'C:\Windows\MEMORY.DMP' -ErrorAction SilentlyContinue |
        Select-Object FullName, Length, LastWriteTime)
}
catch { }

$rows = @($selected | ForEach-Object {
    [pscustomobject]@{
        Time = $_.TimeCreated.ToString('o')
        Id = $_.Id
        Provider = $_.ProviderName
        Level = $_.LevelDisplayName
        Message = ($_.Message -replace '\s+', ' ').Trim()
    }
})

$payload = [pscustomobject]@{
    Generated = (Get-Date).ToString('o')
    Boot = $boot.ToString('o')
    WindowStart = $from.ToString('o')
    WindowEnd = $to.ToString('o')
    WheaCount = $whea.Count
    KernelPower41Count = $power41.Count
    ThermalEventCount = $thermal.Count
    NvidiaErrorCount = $nvidia.Count
    Tcpip4231Count = $network.Count
    WmiActivityCount = $wmi.Count
    Events = $rows
    Whea = @($whea | ForEach-Object { [pscustomobject]@{ Time = $_.TimeCreated.ToString('o'); Id = $_.Id; Message = $_.Message; Xml = $_.ToXml() } })
    KernelPower41 = @($power41 | ForEach-Object { [pscustomobject]@{ Time = $_.TimeCreated.ToString('o'); Message = $_.Message; Xml = $_.ToXml() } })
    Minidumps = @($dumps)
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $OutDir ('incident-{0}.json' -f $stamp)
$text = Join-Path $OutDir ('incident-{0}.txt' -f $stamp)
$payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $json -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('BNQQ INCIDENT TRIAGE')
$lines.Add(('Generated: {0}' -f $payload.Generated))
$lines.Add(('Boot: {0}' -f $payload.Boot))
$lines.Add(('Window: {0} -> {1}' -f $payload.WindowStart, $payload.WindowEnd))
$lines.Add(('WHEA 18: {0} | Kernel-Power 41: {1} | Thermal: {2} | nvlddmkm: {3} | Tcpip 4231: {4}' -f $payload.WheaCount, $payload.KernelPower41Count, $payload.ThermalEventCount, $payload.NvidiaErrorCount, $payload.Tcpip4231Count))
$lines.Add('')
foreach ($e in $rows) {
    $lines.Add(('[{0}] {1} {2} ({3}): {4}' -f $e.Time, $e.Id, $e.Provider, $e.Level, $e.Message))
}
$lines | Set-Content -LiteralPath $text -Encoding UTF8

Write-Host ''
Write-Host '  INCIDENT TRIAGE' -ForegroundColor Cyan
Write-Host ('    Window       {0} -> {1}' -f $from.ToString('yyyy-MM-dd HH:mm:ss'), $to.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Gray
Write-Host ('    WHEA 18      {0}' -f $payload.WheaCount) -ForegroundColor $(if ($payload.WheaCount) { 'Red' } else { 'Green' })
Write-Host ('    Kernel 41    {0}' -f $payload.KernelPower41Count) -ForegroundColor $(if ($payload.KernelPower41Count) { 'Red' } else { 'Gray' })
Write-Host ('    Thermal      {0}' -f $payload.ThermalEventCount) -ForegroundColor $(if ($payload.ThermalEventCount) { 'Yellow' } else { 'Gray' })
Write-Host ('    nvlddmkm     {0}' -f $payload.NvidiaErrorCount) -ForegroundColor $(if ($payload.NvidiaErrorCount) { 'Yellow' } else { 'Gray' })
Write-Host ('    Tcpip 4231   {0}' -f $payload.Tcpip4231Count) -ForegroundColor $(if ($payload.Tcpip4231Count) { 'Yellow' } else { 'Gray' })
Write-Host ('    JSON         {0}' -f $json) -ForegroundColor Gray
Write-Host ('    TXT          {0}' -f $text) -ForegroundColor Gray
Write-Host ''
return $payload
