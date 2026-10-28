# update-font.ps1
# Rebuild the subset of HarmonyOS Sans used for headings / UI.
# Usage (in D:\blog\myblog):
#   powershell -ExecutionPolicy Bypass -File .\update-font.ps1
# Needs: python + fonttools + brotli, and the original font at fonts-src\HarmonyOS-Sans.woff2

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$src = "fonts-src\HarmonyOS-Sans.woff2"
$out = "static\fonts\HarmonyOS-Sans-sub.woff2"
$charFile = "title-chars.txt"

if (-not (Test-Path $src)) {
    Write-Host "Original font not found: $src" -ForegroundColor Red
    exit 1
}

$sb = New-Object System.Text.StringBuilder

# 1. Titles, descriptions and markdown headings of all posts
if (Test-Path "content") {
    Get-ChildItem content -Recurse -Include *.md | ForEach-Object {
        Get-Content $_.FullName -Encoding UTF8 | Where-Object {
            $_ -match '^\s*(title|description):' -or $_ -match '^#{1,6}\s'
        } | ForEach-Object { [void]$sb.AppendLine($_) }
    }
}

# 2. Site config (sidebar text, menu names, ...)
if (Test-Path "config") {
    Get-ChildItem config -Recurse -File | ForEach-Object {
        [void]$sb.AppendLine((Get-Content $_.FullName -Raw -Encoding UTF8))
    }
}

# 3. Theme Chinese UI strings
$i18n = "themes\hugo-theme-stack\i18n\zh.toml"
if (Test-Path $i18n) {
    [void]$sb.AppendLine((Get-Content $i18n -Raw -Encoding UTF8))
}

# 4. ASCII letters, digits and punctuation
for ($c = 32; $c -le 126; $c++) { [void]$sb.Append([char]$c) }

# 5. CJK / fullwidth punctuation (kept as code point ranges so this file stays ASCII-only)
foreach ($range in @(@(0x2000, 0x206F), @(0x3000, 0x303F), @(0xFF00, 0xFFEF))) {
    for ($c = $range[0]; $c -le $range[1]; $c++) { [void]$sb.Append([char]$c) }
}

# 6. The 3755 most common Chinese characters (GB2312 level 1), so new titles rarely miss a glyph
try { [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance) } catch {}
$gb = [System.Text.Encoding]::GetEncoding(936)
for ($hi = 0xB0; $hi -le 0xD7; $hi++) {
    $maxLo = 0xFE
    if ($hi -eq 0xD7) { $maxLo = 0xF9 }
    for ($lo = 0xA1; $lo -le $maxLo; $lo++) {
        [void]$sb.Append($gb.GetString([byte[]]@($hi, $lo)))
    }
}

# Deduplicate and save
$chars = -join ([char[]]$sb.ToString() | Where-Object { $_ -notmatch '[\r\n]' } | Select-Object -Unique)
[System.IO.File]::WriteAllText($charFile, $chars, (New-Object System.Text.UTF8Encoding $false))
Write-Host ("Characters kept: " + $chars.Length)

# Build the subset
if (Get-Command pyftsubset -ErrorAction SilentlyContinue) {
    pyftsubset $src --text-file=$charFile --flavor=woff2 --output-file=$out
} else {
    python -m fontTools.subset $src --text-file=$charFile --flavor=woff2 --output-file=$out
}

Write-Host ("Done: " + $out + " = " + (Get-Item $out).Length + " bytes")
