$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$targets = @(
    Get-ChildItem -LiteralPath $root -Filter '*.html' -File
    Get-Item -LiteralPath (Join-Path $PSScriptRoot 'build_dynamic_gallery.py')
)

$pattern = '<svg class="tree-logo" viewBox="0 0 72 72"[^>]*>.*?</svg>'
$replacement = @'
<svg class="tree-logo" viewBox="0 0 72 72" aria-hidden="true"><path d="M13 31C7 25 12 15 22 17C24 8 37 7 42 14C51 9 61 17 58 26C66 31 60 43 51 42H20C10 44 5 36 13 31Z" fill="currentColor" opacity=".95"/><path d="M34 62C34 53 35 45 31 37M38 62C38 53 37 45 43 37M36 46L25 35M37 44L49 32M36 62L24 68M36 62L48 68M36 61L31 69M37 61L42 69" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/></svg>
'@

$utf8NoBom = [Text.UTF8Encoding]::new($false)
$updated = 0

foreach ($target in $targets) {
    $text = [IO.File]::ReadAllText($target.FullName)
    $matches = [regex]::Matches(
        $text,
        $pattern,
        [Text.RegularExpressions.RegexOptions]::Singleline
    )

    if ($matches.Count -eq 0) {
        continue
    }
    if ($matches.Count -ne 1) {
        throw "Expected one header SVG in $($target.FullName), found $($matches.Count)"
    }

    $newText = [regex]::Replace(
        $text,
        $pattern,
        $replacement,
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    [IO.File]::WriteAllText($target.FullName, $newText, $utf8NoBom)
    $updated++
}

Write-Host "Updated rooted oak header logo in $updated files."
