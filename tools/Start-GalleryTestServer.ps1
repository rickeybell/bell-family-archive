param(
    [string]$TestRoot = "website-test-v38",
    [int]$Port = 8765
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Root = (Resolve-Path (Join-Path $RepoRoot $TestRoot)).Path
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,$Port)
$listener.Start()
$url = "http://127.0.0.1:$Port/gallery-test.html"
Write-Host "Serving: $Root"
Write-Host "Open:    $url"
Write-Host "Press Ctrl+C to stop."
Start-Process $url

function Get-ContentType([string]$path) {
    switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
        '.html' {'text/html; charset=utf-8'}
        '.css' {'text/css; charset=utf-8'}
        '.js' {'application/javascript; charset=utf-8'}
        '.json' {'application/json; charset=utf-8'}
        '.jpg' {'image/jpeg'}
        '.jpeg' {'image/jpeg'}
        '.png' {'image/png'}
        '.gif' {'image/gif'}
        '.webp' {'image/webp'}
        '.tif' {'image/tiff'}
        '.tiff' {'image/tiff'}
        default {'application/octet-stream'}
    }
}

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = New-Object IO.StreamReader($stream,[Text.Encoding]::ASCII,$false,4096,$true)
            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($requestLine)) { $client.Close(); continue }
            while (($line=$reader.ReadLine()) -ne '') { if ($null -eq $line) { break } }
            $parts = $requestLine.Split(' ')
            $rawPath = if ($parts.Count -ge 2) { $parts[1] } else { '/' }
            $pathOnly = [Uri]::UnescapeDataString(($rawPath -split '\?')[0])
            if ($pathOnly -eq '/') { $pathOnly='/gallery-test.html' }
            $relative = $pathOnly.TrimStart('/') -replace '/', [IO.Path]::DirectorySeparatorChar
            $file = [IO.Path]::GetFullPath((Join-Path $Root $relative))
            if (!$file.StartsWith($Root,[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $file -PathType Leaf)) {
                $body=[Text.Encoding]::UTF8.GetBytes('404 Not Found')
                $header="HTTP/1.1 404 Not Found`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
                $hb=[Text.Encoding]::ASCII.GetBytes($header);$stream.Write($hb,0,$hb.Length);$stream.Write($body,0,$body.Length);continue
            }
            $bytes=[IO.File]::ReadAllBytes($file)
            $contentType=Get-ContentType $file
            $extra=''
            if ($relative -match '^(?i)originals[\\/]') {
                $safeName=[IO.Path]::GetFileName($file).Replace('"','')
                $extra="Content-Disposition: attachment; filename=`"$safeName`"`r`n"
            }
            $header="HTTP/1.1 200 OK`r`nContent-Type: $contentType`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-store`r`n$extra`r`n"
            $hb=[Text.Encoding]::ASCII.GetBytes($header);$stream.Write($hb,0,$hb.Length);$stream.Write($bytes,0,$bytes.Length)
        } catch { Write-Warning $_.Exception.Message } finally { $client.Close() }
    }
} finally { $listener.Stop() }
