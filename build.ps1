[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$Version = '1.4.0',
    [switch]$KeepBuild
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$buildDir = Join-Path $root 'build'
$staging = Join-Path $buildDir 'payload'
$zipPath = Join-Path $buildDir 'payload.zip'
$csPath = Join-Path $buildDir 'Launcher.cs'
$manifestPath = Join-Path $buildDir 'BNQQ_Optimizer.manifest'
if (-not $OutputPath) { $OutputPath = Join-Path $root 'dist\BNQQ_Optimizer.exe' }
if (-not [IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $root $OutputPath }

$required = @('bnqq.ps1', 'bnqq-watch.ps1', 'bnqq-audio.ps1', 'lib', 'config')
foreach ($item in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $item))) { throw "Item obrigatorio ausente: $item" }
}

$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$csc = Join-Path $framework 'csc.exe'
$compressionRef = Join-Path $framework 'System.IO.Compression.FileSystem.dll'
if (-not (Test-Path -LiteralPath $csc)) { throw "csc.exe nao encontrado em $framework" }
if (-not (Test-Path -LiteralPath $compressionRef)) { throw "System.IO.Compression.FileSystem.dll nao encontrado em $framework" }

if (Test-Path -LiteralPath $buildDir) { Remove-Item -LiteralPath $buildDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null

foreach ($item in @('bnqq.ps1', 'bnqq-watch.ps1', 'bnqq-audio.ps1')) {
    Copy-Item -LiteralPath (Join-Path $root $item) -Destination (Join-Path $staging $item) -Force
}
if (Test-Path -LiteralPath (Join-Path $root 'license.key')) {
    Copy-Item -LiteralPath (Join-Path $root 'license.key') -Destination (Join-Path $staging 'license.key') -Force
}
foreach ($item in @('lib', 'config')) {
    Copy-Item -LiteralPath (Join-Path $root $item) -Destination (Join-Path $staging $item) -Recurse -Force
}

$payloadStamp = [Guid]::NewGuid().ToString('N')
$payloadStamp | Set-Content -LiteralPath (Join-Path $staging 'payload.stamp') -Encoding ASCII
$tar = Get-Command tar.exe -ErrorAction SilentlyContinue
if ($tar) {
    & $tar.Source -a -c -f $zipPath -C $staging .
    if ($LASTEXITCODE -ne 0) { throw "Falha ao criar payload.zip (tar exit $LASTEXITCODE)" }
}
else {
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force
}

$csharp = @'
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;

namespace BnqqLauncher
{
    internal static class Program
    {
        private const string AppVersion = "__APP_VERSION__";
        private const string PayloadStamp = "__PAYLOAD_STAMP__";

        private static int Main(string[] args)
        {
            try
            {
                string baseDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "BNQQ_Optimizer",
                    AppVersion);
                string script = Path.Combine(baseDir, "bnqq.ps1");
                string stampPath = Path.Combine(baseDir, "payload.stamp");
                bool current = File.Exists(script) && File.Exists(stampPath)
                    && File.ReadAllText(stampPath).Trim() == PayloadStamp;

                if (!current)
                {
                    if (Directory.Exists(baseDir))
                    {
                        try { Directory.Delete(baseDir, true); } catch { }
                    }
                    Directory.CreateDirectory(baseDir);

                    string zip = Path.Combine(Path.GetTempPath(), "bnqq-payload-" + Guid.NewGuid().ToString("N") + ".zip");
                    using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
                    {
                        if (resource == null) throw new InvalidOperationException("payload.zip ausente no executavel");
                        using (FileStream file = File.Create(zip)) { resource.CopyTo(file); }
                    }

                    try { ZipFile.ExtractToDirectory(zip, baseDir); }
                    finally { try { File.Delete(zip); } catch { } }
                    File.WriteAllText(stampPath, PayloadStamp);
                }

                if (args.Length > 0 && string.Equals(args[0], "--check", StringComparison.OrdinalIgnoreCase))
                {
                    Console.WriteLine("payload=" + baseDir);
                    Console.WriteLine("script=" + script);
                    return 0;
                }

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"";
                psi.WorkingDirectory = baseDir;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = false;

                using (Process child = Process.Start(psi))
                {
                    child.WaitForExit();
                    if (child.ExitCode != 0)
                    {
                        Console.WriteLine();
                        Console.WriteLine("BNQQ finalizado com codigo " + child.ExitCode + ".");
                        Console.WriteLine("Pressione Enter para fechar...");
                        Console.ReadLine();
                    }
                    return child.ExitCode;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("Falha ao iniciar BNQQ: " + ex.Message);
                Console.WriteLine("Pressione Enter para fechar...");
                Console.ReadLine();
                return 1;
            }
        }
    }
}
'@
$csharp = $csharp.Replace('__APP_VERSION__', $Version).Replace('__PAYLOAD_STAMP__', $payloadStamp)
$csharp | Set-Content -LiteralPath $csPath -Encoding UTF8

$manifest = @'
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="BNQQ.Optimizer"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
    </application>
  </compatibility>
</assembly>
'@
$manifest | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$arguments = @(
    '/nologo',
    '/target:exe',
    '/platform:anycpu',
    '/optimize+',
    "/out:$OutputPath",
    "/win32manifest:$manifestPath",
    "/resource:$zipPath,payload.zip",
    "/reference:$compressionRef",
    $csPath
)

& $csc $arguments
if ($LASTEXITCODE -ne 0) { throw "Falha na compilacao C# (csc exit $LASTEXITCODE)" }
if (-not (Test-Path -LiteralPath $OutputPath)) { throw "Executavel nao gerado: $OutputPath" }

$info = Get-Item -LiteralPath $OutputPath
Write-Host ('BNQQ_Optimizer.exe gerado: {0}' -f $info.FullName) -ForegroundColor Green
Write-Host ('Tamanho: {0:N0} bytes' -f $info.Length) -ForegroundColor Gray
Write-Host 'Manifesto: requireAdministrator (UAC ao clicar)' -ForegroundColor Gray

if (-not $KeepBuild) {
    Remove-Item -LiteralPath $buildDir -Recurse -Force -ErrorAction SilentlyContinue
}
