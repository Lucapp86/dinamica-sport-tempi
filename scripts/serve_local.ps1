param(
    [int]$Port = 8765,
    [switch]$NoOpen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = [System.IO.Path]::GetFullPath((Split-Path -Parent $scriptDir))

$mimeTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".webmanifest" = "application/manifest+json; charset=utf-8"
    ".svg"  = "image/svg+xml"
    ".png"  = "image/png"
    ".ico"  = "image/x-icon"
}

$listener = New-Object System.Net.HttpListener
$prefix = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)
$listener.Start()

Write-Host "Server locale Dinamica Sport avviato su $prefix"
Write-Host "Premi CTRL+C per chiudere."

if (-not $NoOpen) {
    Start-Process $prefix
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $reqPath = $ctx.Request.Url.AbsolutePath.TrimStart('/')
        if ([string]::IsNullOrWhiteSpace($reqPath)) { $reqPath = "index.html" }

        $safeRel = $reqPath -replace '/', [System.IO.Path]::DirectorySeparatorChar
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $rootDir $safeRel))

        if (-not $fullPath.StartsWith($rootDir, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $fullPath -PathType Leaf)) {
            $ctx.Response.StatusCode = 404
            $errBytes = [System.Text.Encoding]::UTF8.GetBytes("Not found")
            $ctx.Response.OutputStream.Write($errBytes, 0, $errBytes.Length)
            $ctx.Response.OutputStream.Close()
            continue
        }

        $ext = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
        $ctx.Response.ContentType = if ($mimeTypes.ContainsKey($ext)) { $mimeTypes[$ext] } else { "application/octet-stream" }
        $ctx.Response.Headers.Add("Cache-Control", "no-store")
        $bytes = [System.IO.File]::ReadAllBytes($fullPath)
        $ctx.Response.ContentLength64 = $bytes.Length
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $ctx.Response.OutputStream.Close()
    }
} finally {
    $listener.Stop()
    $listener.Close()
}

