# add-inbox.ps1  (pure ASCII on purpose, safe for Windows PowerShell 5.1)
# Put this file next to add-gallery.ps1 (repo root, e.g. D:\blog\myblog).
# Usage: put new images into the inbox folder, then run  .\add-inbox.ps1
#   1) runs add-gallery.ps1 on the inbox only (old images are not scanned again)
#   2) if the manifest was committed and pushed, moves the inbox files into the archive folder
#   3) clears gallery-out (R2 already has those files)

param(
    [string]$Inbox   = "D:\blog-assets\inbox",
    [string]$Archive = "D:\blog-assets\waifus"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path $Inbox)) {
    New-Item -ItemType Directory -Path $Inbox | Out-Null
    Write-Host ("Inbox created: {0}" -f $Inbox)
    Write-Host "Put new images there (no sub folders), then run this script again."
    exit 0
}
if (-not (Test-Path $Archive)) {
    New-Item -ItemType Directory -Path $Archive | Out-Null
}

$files = @(Get-ChildItem -LiteralPath $Inbox -File | Where-Object { $_.Extension -match '^\.(jpe?g|png|webp|gif|avif|bmp)$' })
if ($files.Count -eq 0) {
    Write-Host "Inbox is empty, nothing to do."
    exit 0
}
Write-Host ("Found {0} new images in the inbox." -f $files.Count)

& "$PSScriptRoot\add-gallery.ps1" -Src $Inbox

# Only archive when the manifest is committed and pushed
$dirty = @(git status --porcelain -- data/waifus.json)
$ahead = 0
$aheadText = git rev-list --count "@{u}..HEAD" 2>$null
if ($aheadText) { $ahead = [int]$aheadText }

if ($dirty.Count -gt 0 -or $ahead -gt 0) {
    Write-Host ""
    Write-Host "The manifest is not pushed yet, so the inbox was NOT archived."
    Write-Host "Fix the problem (or run git push), then run this script again."
    exit 1
}

foreach ($f in $files) {
    $dest = Join-Path $Archive $f.Name
    if (Test-Path -LiteralPath $dest) {
        $stamp = Get-Date -Format "yyyyMMddHHmmss"
        $dest = Join-Path $Archive ("{0}_{1}{2}" -f $f.BaseName, $stamp, $f.Extension)
    }
    Move-Item -LiteralPath $f.FullName -Destination $dest
}

$out = Join-Path $PSScriptRoot "gallery-out"
if (Test-Path $out) {
    Get-ChildItem -LiteralPath $out -Force | Remove-Item -Recurse -Force
}

Write-Host ""
Write-Host ("Done: {0} images added, archived to {1}" -f $files.Count, $Archive)
