# Bell Family Archive

Private working repository for the Bell Family genealogy website.

The site is a static HTML/CSS/JavaScript family archive. The working source will be published from the repository root when GitHub Pages is enabled.

## Workflow

- `index.html` — family tree landing page
- individual family-member `.html` pages — personal archives
- `style.css` — site and family-tree styling
- `site.js` / `person.js` — site interactions
- `images/` — web image copies

Genealogy originals should remain preserved separately; the website can use web-sized copies so the repository stays manageable.

## Fast media export

Install the photo-export dependency once:

```powershell
python -m pip install -r requirements-export.txt
```

Routine updates are incremental and use four concurrent photo workers:

```powershell
.\Update-BellWebsite.ps1
```

Run a complete integrity and metadata audit when needed:

```powershell
.\Update-BellWebsite.ps1 -FullAudit
```

Force every selected photo derivative to be regenerated only when export settings or the image engine require it:

```powershell
.\Update-BellWebsite.ps1 -FullAudit -ForcePhotoRebuild
```

Publish already-prepared website changes with:

```powershell
.\Publish-BellWebsite.ps1 -CommitMessage "Describe the website update"
```

Both publishing paths update and verify digiKam's green color labels for every
Website-tagged item before committing or pushing. If the digiKam update fails,
the website publish stops.

Local derivative and video-probe caches are ignored by Git. Deleting either cache is safe; the next run rebuilds it. The scripts derive the repository location from their own files, so the checkout can live outside OneDrive without path changes.
