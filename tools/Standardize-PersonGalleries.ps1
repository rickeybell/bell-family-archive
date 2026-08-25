$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$metadata = Get-Content -LiteralPath (Join-Path $root 'photo_metadata.json') -Raw | ConvertFrom-Json
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$singleline = [Text.RegularExpressions.RegexOptions]::Singleline

$profiles = @(
    @{ Slug = 'alma';      Person = 'Alma Bell';          Label = 'Alma' }
    @{ Slug = 'breana';    Person = 'Anna Lear';          Label = 'BreeAna' }
    @{ Slug = 'buster';    Person = 'Buster Bell';        Label = 'Buster' }
    @{ Slug = 'charlie';   Person = 'Charlie Brown';      Label = 'Charlie' }
    @{ Slug = 'debbie';    Person = 'Debbie Phillips';    Label = 'Debbie' }
    @{ Slug = 'dickey';    Person = 'Dickey Bell';        Label = 'Dickey' }
    @{ Slug = 'dominique'; Person = 'Dominique Burwell';  Label = 'Dominique' }
    @{ Slug = 'donna';     Person = 'Donna Brown';        Label = 'Donna' }
    @{ Slug = 'heather';   Person = 'Heather Bell';       Label = 'Heather' }
    @{ Slug = 'helen';     Person = 'Helen Bell';         Label = 'Helen' }
    @{ Slug = 'irvin';     Person = 'Irvin Phillips';     Label = 'Irvin' }
    @{ Slug = 'ivy';       Person = 'Ivy Bell';           Label = 'Ivy' }
    @{ Slug = 'jarred';    Person = 'Jarred Bell';        Label = 'Jarred' }
    @{ Slug = 'olivia';    Person = 'Olivia Bell';        Label = 'Olivia' }
    @{ Slug = 'rickey';    Person = 'Rickey Bell';        Label = 'Rickey' }
    @{ Slug = 'rickii';    Person = 'Rickii Lear';        Label = 'Rickii' }
    @{ Slug = 'samatha';   Person = 'Samatha Bell';       Label = 'Samatha' }
    @{ Slug = 'sonja';     Person = 'Sonja Bell';         Label = 'Sonja' }
    @{ Slug = 'sophia';    Person = 'Sophia Bell';        Label = 'Sophia' }
    @{ Slug = 'spooky';    Person = 'Spooky Bell';        Label = 'Spooky' }
    @{ Slug = 'stephanie'; Person = 'Stephanie Bell';     Label = 'Stephanie' }
    @{ Slug = 'xavier';    Person = 'Xavier Lear';        Label = 'Xavier' }
)

foreach ($profile in $profiles) {
    $pagePath = Join-Path $root ($profile.Slug + '.html')
    if (-not (Test-Path -LiteralPath $pagePath)) {
        throw "Missing profile page: $pagePath"
    }

    $count = @($metadata | Where-Object { $_.people -contains $profile.Person }).Count
    $html = [IO.File]::ReadAllText($pagePath)

    $html = [regex]::Replace(
        $html,
        '<section class="tree-note"[^>]*data-current-photo-gallery="true"[^>]*>.*?</section>\s*',
        '',
        $singleline
    )
    $html = [regex]::Replace(
        $html,
        '<section class="tree-note"[^>]*>\s*<h2>Current Photo Archive</h2>.*?</section>\s*',
        '',
        $singleline
    )
    $html = [regex]::Replace(
        $html,
        '<section class="embedded-archive"[^>]*>.*?</section>\s*',
        '',
        $singleline
    )
    if ($profile.Slug -eq 'dickey') {
        $html = [regex]::Replace(
            $html,
            '<section id="archive"><h2>Chronological Photo &amp; Document Archive</h2>.*?</section>\s*',
            '',
            $singleline
        )
    }

    $countPattern = '<div class="person-count"[^>]*>.*?</div>'
    if ([regex]::IsMatch($html, $countPattern, $singleline)) {
        $countText = if ($count -eq 1) { '1 currently identified archive item' } else { "$count currently identified archive items" }
        $countMarkup = '<div class="person-count" data-archive-person="' + $profile.Person + '">' + $countText + '</div>'
        $html = [regex]::Replace($html, $countPattern, $countMarkup, $singleline)
    }

    $itemWord = if ($count -eq 1) { 'item' } else { 'items' }
    $section = @"

<section class="embedded-archive" id="archive" aria-labelledby="$($profile.Slug)-archive-title">
  <div class="embedded-archive-heading">
    <div class="eyebrow">Bell Family Archive</div>
    <h2 id="$($profile.Slug)-archive-title">$($profile.Label)&rsquo;s Photo Gallery</h2>
    <p>Browse $($profile.Label)&rsquo;s $count currently identified archive $itemWord below.</p>
  </div>
  <div class="embedded-archive-content" data-gallery-source="$($profile.Slug)-photos.html" data-gallery-name="$($profile.Label)" aria-busy="true">
    <p class="embedded-archive-loading">Loading $($profile.Label)&rsquo;s photo gallery&hellip;</p>
  </div>
</section>

"@

    $html = $html.Replace('</main>', $section + '</main>')
    $html = [regex]::Replace(
        $html,
        '<a([^>]*?)href="[^"]*"([^>]*?)>Photo Gallery</a>',
        '<a$1href="#archive"$2>Photo Gallery</a>',
        $singleline
    )
    $html = $html.Replace('<script src="sonja-gallery.js"></script>', '')
    if (-not $html.Contains('<script src="embedded-gallery.js"></script>')) {
        if ($html.Contains('<script src="person.js"></script>')) {
            $html = $html.Replace(
                '<script src="person.js"></script>',
                '<script src="embedded-gallery.js"></script><script src="person.js"></script>'
            )
        }
        elseif ($html.Contains('<script src="site.js"></script>')) {
            $html = $html.Replace(
                '<script src="site.js"></script>',
                '<script src="embedded-gallery.js"></script><script src="site.js"></script>'
            )
        }
        else {
            $html = $html.Replace('</body>', '<script src="embedded-gallery.js"></script></body>')
        }
    }

    [IO.File]::WriteAllText($pagePath, $html, $utf8NoBom)
    Write-Host "$($profile.Slug).html: $count archive $itemWord"
}
