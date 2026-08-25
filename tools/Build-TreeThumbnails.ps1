param(
    [int]$MaxDimension = 640,
    [ValidateRange(1, 100)]
    [int]$JpegQuality = 84,
    [switch]$SkipIndexUpdate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$indexPath = Join-Path $root 'index.html'
$sourceDir = Join-Path $root 'tree_portraits'
$outputDir = Join-Path $root 'tree_thumbs'

if (-not (Test-Path -LiteralPath $indexPath)) {
    throw "Could not find $indexPath"
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$html = [IO.File]::ReadAllText($indexPath)
$references = @(
    [regex]::Matches($html, 'tree_(?:portraits|thumbs)/[^"'']+') |
        ForEach-Object { $_.Value } |
        Sort-Object -Unique
)

$sourceByStem = @{}
Get-ChildItem -LiteralPath $sourceDir -File | ForEach-Object {
    if ($sourceByStem.ContainsKey($_.BaseName)) {
        throw "Duplicate portrait stem '$($_.BaseName)' in $sourceDir"
    }
    $sourceByStem[$_.BaseName] = $_.FullName
}

$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
    Where-Object { $_.MimeType -eq 'image/jpeg' } |
    Select-Object -First 1
$encoderParameters = [System.Drawing.Imaging.EncoderParameters]::new(1)
$encoderParameters.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new(
    [System.Drawing.Imaging.Encoder]::Quality,
    [long]$JpegQuality
)

$sourceBytes = 0L
$outputBytes = 0L
$generated = 0
$updatedHtml = $html

try {
    foreach ($reference in $references) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($reference)
        if (-not $sourceByStem.ContainsKey($stem)) {
            throw "No original portrait found for '$reference'"
        }

        $sourcePath = $sourceByStem[$stem]
        $destinationName = "$stem.jpg"
        $destinationPath = Join-Path $outputDir $destinationName
        $sourceBytes += (Get-Item -LiteralPath $sourcePath).Length

        $image = [System.Drawing.Image]::FromFile($sourcePath)
        try {
            $scale = [Math]::Min(1.0, $MaxDimension / [double][Math]::Max($image.Width, $image.Height))
            $width = [Math]::Max(1, [int][Math]::Round($image.Width * $scale))
            $height = [Math]::Max(1, [int][Math]::Round($image.Height * $scale))

            $bitmap = [System.Drawing.Bitmap]::new(
                $width,
                $height,
                [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
            )
            try {
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                try {
                    $graphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#e8e3d9'))
                    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                    $graphics.DrawImage(
                        $image,
                        [System.Drawing.Rectangle]::new(0, 0, $width, $height),
                        0,
                        0,
                        $image.Width,
                        $image.Height,
                        [System.Drawing.GraphicsUnit]::Pixel
                    )
                }
                finally {
                    $graphics.Dispose()
                }

                $bitmap.Save($destinationPath, $jpegCodec, $encoderParameters)
            }
            finally {
                $bitmap.Dispose()
            }
        }
        finally {
            $image.Dispose()
        }

        $outputBytes += (Get-Item -LiteralPath $destinationPath).Length
        $generated++
        $updatedHtml = $updatedHtml.Replace($reference, "tree_thumbs/$destinationName")
    }
}
finally {
    $encoderParameters.Dispose()
}

if (-not $SkipIndexUpdate) {
    $utf8NoBom = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($indexPath, $updatedHtml, $utf8NoBom)
}

$savedPercent = if ($sourceBytes) {
    [Math]::Round((1 - ($outputBytes / [double]$sourceBytes)) * 100, 1)
} else {
    0
}

Write-Host "Generated $generated tree thumbnails in $outputDir"
Write-Host "Original total: $([Math]::Round($sourceBytes / 1MB, 2)) MB"
Write-Host "Thumbnail total: $([Math]::Round($outputBytes / 1MB, 2)) MB"
Write-Host "Reduction: $savedPercent%"
