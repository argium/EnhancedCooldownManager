<#
.SYNOPSIS
    Fetches external libraries defined in .pkgmeta into the working tree.
.PARAMETER Force
    Remove and re-fetch libraries that already exist.
#>

param([switch]$Force)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot

# --- Parse .pkgmeta externals ---

$pkgmeta = Get-Content (Join-Path $repoRoot ".pkgmeta") -Raw
if ($pkgmeta -notmatch '(?ms)^externals:\s*\n(.*?)(?=^\S|\z)') {
    Write-Host "No externals block found in .pkgmeta" -ForegroundColor Yellow
    return
}

$externals = @()
$curPath = $null; $curUrl = $null; $curTag = $null

foreach ($line in $Matches[1] -split '\r?\n') {
    if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }

    if ($line -match '^  (\S.+?):\s+(\S.+)$') {
        if ($curPath -and $curUrl) { $externals += [PSCustomObject]@{ Path = $curPath; Url = $curUrl; Tag = $curTag } }
        $curPath = $Matches[1].Trim(); $curUrl = $Matches[2].Trim(); $curTag = $null
    }
    elseif ($line -match '^  (\S.+?):\s*$') {
        if ($curPath -and $curUrl) { $externals += [PSCustomObject]@{ Path = $curPath; Url = $curUrl; Tag = $curTag } }
        $curPath = $Matches[1].Trim(); $curUrl = $null; $curTag = $null
    }
    elseif ($line -match '^\s+url:\s+(.+)$') { $curUrl = $Matches[1].Trim() }
    elseif ($line -match '^\s+tag:\s+(.+)$') { $curTag = $Matches[1].Trim() }
}
if ($curPath -and $curUrl) { $externals += [PSCustomObject]@{ Path = $curPath; Url = $curUrl; Tag = $curTag } }

if ($externals.Count -eq 0) {
    Write-Host "No externals found in .pkgmeta" -ForegroundColor Yellow
    return
}

# --- Verify SVN ---

$hasSvn = $externals | Where-Object { $_.Url -match 'repos\.(wowace|curseforge)' }
if ($hasSvn -and -not (Get-Command svn -ErrorAction SilentlyContinue)) {
    Write-Error "SVN required for WoWAce externals. Install via: scoop install sliksvn"
}

Write-Host "Fetching $($externals.Count) externals..." -ForegroundColor Cyan

# --- Fetch each external ---

foreach ($ext in $externals) {
    $target = Join-Path $repoRoot $ext.Path

    if ((Test-Path $target) -and -not $Force) {
        Write-Host "  SKIP  $($ext.Path)" -ForegroundColor DarkGray
        continue
    }
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }

    $label = $ext.Tag ?? 'HEAD'

    if ($ext.Url -match 'github\.com/([^/]+)/([^/]+?)(?:\.git)?$') {
        # GitHub: download source archive for the pinned tag.
        # Extra repo files (tests, CI) are inert — WoW only loads what
        # XML/TOC references. The packager strips them for releases.
        $owner = $Matches[1]; $repo = $Matches[2]
        $ref = $ext.Tag ?? 'HEAD'
        $zipUrl = "https://github.com/$owner/$repo/archive/refs/tags/$ref.zip"
        $zipFile = Join-Path ([IO.Path]::GetTempPath()) "$repo.zip"

        Write-Host "  GET   $($ext.Path)  @ $label" -ForegroundColor Green
        Invoke-WebRequest $zipUrl -OutFile $zipFile -UseBasicParsing

        $extractDir = Join-Path ([IO.Path]::GetTempPath()) "ecm-extract"
        Expand-Archive $zipFile -DestinationPath $extractDir -Force
        $inner = Get-ChildItem $extractDir | Select-Object -First 1
        Move-Item $inner.FullName $target

        Remove-Item $zipFile, $extractDir -Recurse -Force
    }
    else {
        # SVN: URL already points to the distributable subdirectory.
        Write-Host "  SVN   $($ext.Path)  @ $label" -ForegroundColor Green
        & svn export --force $ext.Url $target 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Error "svn export failed for $($ext.Path)" }
    }
}

Write-Host "Done." -ForegroundColor Cyan
