# Gallery preprocessing: make thumbnails + full images (webp), write data/waifus.json
# Usage (in blog root):
#   powershell -ExecutionPolicy Bypass -File .\build-gallery.ps1 -Src "D:\path\to\original\images"
# Safe to re-run: images already processed (matched by content hash) are skipped.

param(
    [Parameter(Mandatory = $true)][string]$Src,
    [string]$Out = ".\gallery-out",
    [string]$Manifest = ".\data\waifus.json"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
    Write-Host "magick not found. Install ImageMagick: winget install ImageMagick.ImageMagick (then reopen PowerShell)"
    exit 1
}
if (-not (Test-Path $Src)) {
    Write-Host "Source folder not found: $Src"
    exit 1
}

New-Item -ItemType Directory -Force -Path "$Out\full", "$Out\thumb" | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $Manifest) | Out-Null

# Load existing manifest for incremental runs
$entries = @{}
if (Test-Path $Manifest) {
    $old = Get-Content $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($e in @($old)) {
        if ($e) { $entries[$e.id] = $e }
    }
}

$files = @(Get-ChildItem $Src -File | Where-Object { $_.Extension -match '^\.(jpe?g|png|webp|gif|bmp|avif)$' })
$total = $files.Count
$n = 0

foreach ($f in $files) {
    $n++
    $id = (Get-FileHash $f.FullName -Algorithm MD5).Hash.Substring(0, 10).ToLower()
    if ($entries.ContainsKey($id)) { continue }

    if ($f.Extension -ieq ".gif") {
        # Keep GIFs untouched so animation is preserved
        $ext = "gif"
        Copy-Item $f.FullName ("{0}\full\{1}.{2}" -f $Out, $id, $ext) -Force
        Copy-Item $f.FullName ("{0}\thumb\{1}.{2}" -f $Out, $id, $ext) -Force
    } else {
        $ext = "webp"
        $fullPath = "{0}\full\{1}.{2}" -f $Out, $id, $ext
        $thumbOut = "{0}\thumb\{1}.{2}" -f $Out, $id, $ext
        magick $f.FullName -auto-orient -resize "2000x2000>" -quality 82 $fullPath
        magick $f.FullName -auto-orient -resize "640x900>" -quality 80 $thumbOut
    }

    $thumbPath = "{0}\thumb\{1}.{2}[0]" -f $Out, $id, $ext
    $dim = (magick identify -format "%w %h" $thumbPath).Trim().Split(" ")
    $fileName = "{0}.{1}" -f $id, $ext

    $entries[$id] = [pscustomobject]@{
        id = $id
        f  = $fileName
        t  = $fileName
        w  = [int]$dim[0]
        h  = [int]$dim[1]
    }
    Write-Host ("[{0}/{1}] {2} -> {3}" -f $n, $total, $f.Name, $fileName)
}

$list = @($entries.Values | Sort-Object id)
$json = ConvertTo-Json -InputObject $list -Depth 3
$manifestFull = Join-Path (Resolve-Path (Split-Path $Manifest)).Path (Split-Path $Manifest -Leaf)
[IO.File]::WriteAllText($manifestFull, $json, (New-Object System.Text.UTF8Encoding $false))

Write-Host ""
Write-Host ("Done: {0} images in manifest, written to {1}" -f $list.Count, $Manifest)
Write-Host ("Next: upload {0}\full and {0}\thumb to waifus/full and waifus/thumb on your image host" -f $Out)
