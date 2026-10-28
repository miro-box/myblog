# Regenerate the heading font subset HarmonyOS-Sans-sub.woff2
# Usage (in blog root): powershell -ExecutionPolicy Bypass -File .\update-font.ps1
# Needs the full font at fonts-src\HarmonyOS-Sans.woff2

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$src = "fonts-src\HarmonyOS-Sans.woff2"
$out = "static\fonts\HarmonyOS-Sans-sub.woff2"

if (-not (Test-Path $src)) {
    Write-Host "Source font not found: $src . Put the full HarmonyOS-Sans.woff2 into fonts-src first."
    exit 1
}

$sb = New-Object System.Text.StringBuilder

# 1. Titles, headings and descriptions from posts
Get-ChildItem content -Recurse -Include *.md | ForEach-Object {
    Get-Content $_.FullName -Encoding UTF8 |
        Where-Object { $_ -match '^\s*(title|description):' -or $_ -match '^#{1,6}\s' } |
        ForEach-Object { [void]$sb.AppendLine($_) }
}

# 2. Site config and theme zh i18n (menus, sidebar, buttons)
if (Test-Path config) {
    Get-ChildItem config -Recurse -File | ForEach-Object {
        [void]$sb.AppendLine((Get-Content $_.FullName -Raw -Encoding UTF8))
    }
}
$i18n = "themes\hugo-theme-stack\i18n\zh.toml"
if (Test-Path $i18n) { [void]$sb.AppendLine((Get-Content $i18n -Raw -Encoding UTF8)) }

# 3. Digits, letters, ASCII punctuation
[void]$sb.Append(" 0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_/.,:;!?()[]")

# 3b. CJK punctuation written as code points (keeps this file pure ASCII)
$punct = 0xFF0C, 0x3002, 0xFF01, 0xFF1F, 0xFF1A, 0xFF1B, 0x3001, 0xFF08, 0xFF09, 0x3010, 0x3011, 0x300A, 0x300B, 0x201C, 0x201D, 0x2018, 0x2019, 0x2014, 0x2026, 0x00B7
foreach ($cp in $punct) { [void]$sb.Append([char]$cp) }

# 4. Common 3755 Chinese characters (GB2312 level 1) so new titles rarely hit missing glyphs
try { [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance) } catch {}
$gb = [System.Text.Encoding]::GetEncoding("gb2312")
for ($hi = 0xB0; $hi -le 0xD7; $hi++) {
    for ($lo = 0xA1; $lo -le 0xFE; $lo++) {
        if ($hi -eq 0xD7 -and $lo -gt 0xF9) { continue }
        [void]$sb.Append($gb.GetString([byte[]]@($hi, $lo)))
    }
}

# Deduplicate and write the character list
$chars = -join ([char[]]$sb.ToString() | Select-Object -Unique)
[IO.File]::WriteAllText("title-chars.txt", $chars, (New-Object System.Text.UTF8Encoding $false))
Write-Host ("Characters kept: {0}" -f $chars.Length)

# Build the subset font
if (Get-Command pyftsubset -ErrorAction SilentlyContinue) {
    pyftsubset $src --text-file=title-chars.txt --flavor=woff2 --output-file=$out
} else {
    python -m fontTools.subset $src --text-file=title-chars.txt --flavor=woff2 --output-file=$out
}

$size = (Get-Item $out).Length
Write-Host ("Generated {0}, size {1} bytes" -f $out, $size)
