# One-shot gallery update (all-in-one):
#   1. process images -> gallery-out\thumb + gallery-out\full, update data\waifus.json
#   2. upload to R2 with rclone (only adds files, never deletes)
#   3. commit and push data\waifus.json (only if uploads succeeded)
#
# Image rules:
#   - jpg/png/bmp/avif/webp -> thumb (webp, <=640x900) + full (webp, <=2000)
#   - gif -> thumb is a static webp of the first frame, full keeps the animated gif
#   - same file name with different extensions (a.jpg / a.png) = one image, the largest file is kept
#
# Usage (in blog root):
#   powershell -ExecutionPolicy Bypass -File .\add-gallery.ps1
# Options:
#   -Src            folder with original images   (default D:\blog-assets\waifus)
#   -Remote         rclone remote name            (default r2)
#   -Bucket         R2 bucket name                (default blog-img)
#   -ProcessOnly    only process images, do not upload or push
#   -NoPush         process and upload, but do not commit/push
#   -DedupeByName   $false to keep same-name files as separate images (default $true)

param(
    [string]$Src = "D:\blog-assets\waifus",
    [string]$Remote = "r2",
    [string]$Bucket = "blog-img",
    [string]$Out = ".\gallery-out",
    [string]$Manifest = ".\data\waifus.json",
    [switch]$ProcessOnly,
    [switch]$NoPush,
    [bool]$DedupeByName = $true
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# ---------- checks ----------
if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
    Write-Host "magick not found. Install ImageMagick: winget install ImageMagick.ImageMagick (then reopen PowerShell)"
    exit 1
}
if ((-not $ProcessOnly) -and (-not (Get-Command rclone -ErrorAction SilentlyContinue))) {
    Write-Host "rclone not found. Install it: winget install Rclone.Rclone (then reopen PowerShell)"
    exit 1
}
if (-not (Test-Path $Src)) {
    Write-Host "Source folder not found: $Src"
    exit 1
}

# ---------- helpers ----------
function Invoke-Magick {
    param([string[]]$MagickArgs)
    & magick @MagickArgs
    if ($LASTEXITCODE -ne 0) { throw ("magick failed: " + ($MagickArgs -join " ")) }
}

function Make-Thumb($srcFile, $thumbPath) {
    # [0] = first frame only (matters for gif; harmless for other formats)
    Invoke-Magick @(("{0}[0]" -f $srcFile), "-auto-orient", "-resize", "640x900>", "-quality", "80", $thumbPath)
}

function Get-Dim($path) {
    $raw = & magick identify -format "%w %h" ("{0}[0]" -f $path)
    if ($LASTEXITCODE -ne 0) { throw ("magick identify failed: " + $path) }
    $d = ([string]$raw).Trim().Split(" ")
    return @([int]$d[0], [int]$d[1])
}

function Get-Id($path) {
    return (Get-FileHash $path -Algorithm MD5).Hash.Substring(0, 10).ToLower()
}

# ---------- Step 1: process images ----------
Write-Host "== Step 1/3: processing images =="

New-Item -ItemType Directory -Force -Path "$Out\full", "$Out\thumb" | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $Manifest) | Out-Null
$manifestFull = Join-Path (Resolve-Path (Split-Path $Manifest)).Path (Split-Path $Manifest -Leaf)

# Load existing manifest for incremental runs
$entries = @{}
if (Test-Path $Manifest) {
    $old = Get-Content $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($e in @($old)) {
        if ($e) { $entries[$e.id] = $e }
    }
}

function Save-Manifest {
    $list = @($entries.Values | Sort-Object id)
    $json = ConvertTo-Json -InputObject $list -Depth 3
    [IO.File]::WriteAllText($manifestFull, $json, (New-Object System.Text.UTF8Encoding $false))
    return $list.Count
}

$added = 0
$upgraded = 0
$dupRemoved = 0

try {
    $files = @(Get-ChildItem $Src -File | Where-Object { $_.Extension -match '^\.(jpe?g|png|webp|gif|bmp|avif)$' })

    # Same name + different extension = same image: keep the largest file only
    if ($DedupeByName) {
        $keep = @()
        foreach ($g in ($files | Group-Object { $_.BaseName.ToLower() })) {
            $sorted = @($g.Group | Sort-Object Length -Descending)
            $keep += $sorted[0]
            if ($sorted.Count -lt 2) { continue }

            $keptHash = Get-Id $sorted[0].FullName
            $skipNames = @()
            foreach ($s in $sorted[1..($sorted.Count - 1)]) {
                $skipNames += $s.Name
                $sid = Get-Id $s.FullName
                # If this duplicate was processed in an earlier run, take it out of the manifest
                if (($sid -ne $keptHash) -and $entries.ContainsKey($sid)) {
                    $e = $entries[$sid]
                    foreach ($p in @(("{0}\full\{1}" -f $Out, $e.f), ("{0}\thumb\{1}" -f $Out, $e.t))) {
                        if (Test-Path $p) { Remove-Item $p -Force }
                    }
                    $entries.Remove($sid)
                    $dupRemoved++
                }
            }
            Write-Host ("Same name: keeping {0}, skipping {1}" -f $sorted[0].Name, ($skipNames -join ", "))
        }
        $files = $keep
    }

    $total = $files.Count
    $n = 0

    foreach ($f in $files) {
        $n++
        $id = Get-Id $f.FullName
        $thumbPath = "{0}\thumb\{1}.webp" -f $Out, $id

        if ($entries.ContainsKey($id)) {
            # Upgrade older entries that used the whole gif as thumbnail
            $e = $entries[$id]
            if ($e.t -like "*.gif") {
                Make-Thumb $f.FullName $thumbPath
                $dim = Get-Dim $thumbPath
                $e.t = "{0}.webp" -f $id
                $e.w = $dim[0]
                $e.h = $dim[1]
                $oldThumb = "{0}\thumb\{1}.gif" -f $Out, $id
                if (Test-Path $oldThumb) { Remove-Item $oldThumb -Force }
                $upgraded++
                Write-Host ("[{0}/{1}] upgraded gif thumb: {2}" -f $n, $total, $f.Name)
            }
            continue
        }

        if ($f.Extension -ieq ".gif") {
            $fullName = "{0}.gif" -f $id
            Copy-Item $f.FullName ("{0}\full\{1}" -f $Out, $fullName) -Force
        } else {
            $fullName = "{0}.webp" -f $id
            $fullPath = "{0}\full\{1}" -f $Out, $fullName
            Invoke-Magick @($f.FullName, "-auto-orient", "-resize", "2000x2000>", "-quality", "82", $fullPath)
        }
        Make-Thumb $f.FullName $thumbPath
        $dim = Get-Dim $thumbPath

        $entries[$id] = [pscustomobject]@{
            id = $id
            f  = $fullName
            t  = ("{0}.webp" -f $id)
            w  = $dim[0]
            h  = $dim[1]
        }
        $added++
        Write-Host ("[{0}/{1}] {2} -> {3}" -f $n, $total, $f.Name, $fullName)

        # Save progress regularly so a long run can be stopped and resumed
        if (($added % 25) -eq 0) { [void](Save-Manifest) }
    }

    $count = Save-Manifest
}
catch {
    # Keep whatever was finished, but do not upload or push anything
    try { [void](Save-Manifest) } catch {}
    Write-Host ("Processing failed: " + $_.Exception.Message)
    Write-Host "Stopped. Nothing was uploaded or pushed. Fix the problem and run again (finished images are skipped)."
    exit 1
}

Write-Host ("Processed: {0} new, {1} upgraded, {2} duplicates removed, {3} images in manifest" -f $added, $upgraded, $dupRemoved, $count)

if ($ProcessOnly) {
    Write-Host "-ProcessOnly: skipped upload and push."
    exit 0
}

# ---------- Step 2: upload to R2 ----------
Write-Host ""
Write-Host "== Step 2/3: uploading to R2 =="
$thumbDest = "{0}:{1}/waifus/thumb" -f $Remote, $Bucket
$fullDest = "{0}:{1}/waifus/full" -f $Remote, $Bucket

rclone copy "$Out\thumb" $thumbDest --transfers 8 --progress
if ($LASTEXITCODE -ne 0) {
    Write-Host "Thumb upload failed, stopped. Manifest was NOT pushed."
    exit 1
}
rclone copy "$Out\full" $fullDest --transfers 8 --progress
if ($LASTEXITCODE -ne 0) {
    Write-Host "Full image upload failed, stopped. Manifest was NOT pushed."
    exit 1
}

# ---------- Step 3: commit and push the manifest ----------
Write-Host ""
if ($NoPush) {
    Write-Host "== Step 3/3: skipped (-NoPush). Remember to commit data/waifus.json later. =="
    exit 0
}

Write-Host "== Step 3/3: committing manifest =="
git add data/waifus.json
git diff --cached --quiet -- data/waifus.json
if ($LASTEXITCODE -eq 0) {
    Write-Host "No manifest changes (no new images). Nothing to commit."
    exit 0
}

$msg = "update gallery " + (Get-Date -Format "yyyy-MM-dd HH:mm")
git commit -m $msg -- data/waifus.json
if ($LASTEXITCODE -ne 0) {
    Write-Host "git commit failed."
    exit 1
}
git push
if ($LASTEXITCODE -ne 0) {
    Write-Host "git push failed. Try: git push --set-upstream origin main"
    exit 1
}

Write-Host ""
Write-Host "All done. Cloudflare Pages will rebuild the site in a minute or two."
