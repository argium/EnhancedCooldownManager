<#
.SYNOPSIS
    Fetches external libraries defined in .pkgmeta into the working tree.
.DESCRIPTION
    Parses the .pkgmeta externals block and clones/exports each library
    into the Libs/ folder for local development. Git repos use
    git clone --depth 1; SVN repos use svn export.
.PARAMETER Force
    Remove and re-fetch libraries that already exist.
#>

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot

# --- Parse .pkgmeta externals ---

$pkgmeta = Get-Content -Path (Join-Path $repoRoot ".pkgmeta") -Raw

# Extract the externals block: everything between "externals:" and the next
# top-level key (a line starting with a non-space, non-comment character) or EOF.
if ($pkgmeta -notmatch '(?ms)^externals:\s*\n(.*?)(?=^\S|\z)') {
    Write-Host "No externals block found in .pkgmeta" -ForegroundColor Yellow
    exit 0
}
$externalsBlock = $Matches[1]

# Parse each external entry. Supports both short form (path: url) and
# expanded form (path: \n  url: ... \n  tag: ...).
$externals = @()
$currentPath = $null
$currentUrl = $null
$currentTag = $null

foreach ($line in $externalsBlock -split '\r?\n') {
    # Skip blank/comment lines
    if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }

    if ($line -match '^  (\S.+?):\s*$') {
        # Start of expanded entry (path only, url/tag on following lines)
        if ($currentPath -and $currentUrl) {
            $externals += [PSCustomObject]@{ Path = $currentPath; Url = $currentUrl; Tag = $currentTag }
        }
        $currentPath = $Matches[1].Trim()
        $currentUrl = $null
        $currentTag = $null
    }
    elseif ($line -match '^  (\S.+?):\s+(\S.+)$') {
        # Short form: "  path: url" on one line
        if ($currentPath -and $currentUrl) {
            $externals += [PSCustomObject]@{ Path = $currentPath; Url = $currentUrl; Tag = $currentTag }
        }
        $currentPath = $Matches[1].Trim()
        $currentUrl = $Matches[2].Trim()
        $currentTag = $null
    }
    elseif ($line -match '^\s+url:\s+(.+)$') {
        $currentUrl = $Matches[1].Trim()
    }
    elseif ($line -match '^\s+tag:\s+(.+)$') {
        $currentTag = $Matches[1].Trim()
    }
}
# Flush last entry
if ($currentPath -and $currentUrl) {
    $externals += [PSCustomObject]@{ Path = $currentPath; Url = $currentUrl; Tag = $currentTag }
}

if ($externals.Count -eq 0) {
    Write-Host "No externals found in .pkgmeta" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($externals.Count) externals in .pkgmeta" -ForegroundColor Cyan

# --- Detect repo type ---

function Get-RepoType([string]$url) {
    if ($url -match '\.git$' -or $url -match 'github\.com') { return 'git' }
    if ($url -match 'repos\.(wowace|curseforge)') { return 'svn' }
    return 'unknown'
}

# --- Verify tools ---

$needsSvn = $externals | Where-Object { (Get-RepoType $_.Url) -eq 'svn' }
if ($needsSvn) {
    $svnCmd = Get-Command svn -ErrorAction SilentlyContinue
    if (-not $svnCmd) {
        Write-Host "`nSVN is required for WoWAce/CurseForge externals but was not found." -ForegroundColor Red
        Write-Host "Install via:  scoop install sliksvn" -ForegroundColor Yellow
        exit 1
    }
}

# --- Fetch each external ---

foreach ($ext in $externals) {
    $targetDir = Join-Path $repoRoot $ext.Path
    $exists = Test-Path $targetDir

    if ($exists -and -not $Force) {
        Write-Host "  SKIP  $($ext.Path) (already exists; use -Force to re-fetch)" -ForegroundColor DarkGray
        continue
    }

    if ($exists -and $Force) {
        Write-Host "  DEL   $($ext.Path)" -ForegroundColor DarkYellow
        Remove-Item -Path $targetDir -Recurse -Force
    }

    $type = Get-RepoType $ext.Url

    switch ($type) {
        'git' {
            $cloneArgs = @('clone', '--depth', '1')
            if ($ext.Tag) {
                $cloneArgs += '--branch'
                $cloneArgs += $ext.Tag
            }
            $cloneArgs += $ext.Url
            $cloneArgs += $targetDir

            Write-Host "  GIT   $($ext.Path)  @ $($ext.Tag ?? 'HEAD')" -ForegroundColor Green
            & git @cloneArgs 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Error "git clone failed for $($ext.Path)"
            }
            # Remove .git directory — we don't need nested repos
            $dotGit = Join-Path $targetDir ".git"
            if (Test-Path $dotGit) {
                Remove-Item -Path $dotGit -Recurse -Force
            }
        }
        'svn' {
            $svnUrl = $ext.Url
            if ($ext.Tag -and $ext.Tag -ne 'latest') {
                # For SVN, convert trunk URL to tags URL
                # e.g. .../wow/libstub/trunk -> .../wow/libstub/tags/1.0
                $svnUrl = $svnUrl -replace '/trunk(/.*)?$', "/tags/$($ext.Tag)"
            }
            Write-Host "  SVN   $($ext.Path)  @ $($ext.Tag ?? 'trunk')" -ForegroundColor Green
            & svn export --force $svnUrl $targetDir 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Error "svn export failed for $($ext.Path)"
            }
        }
        default {
            Write-Warning "Unknown repo type for $($ext.Url) — skipping $($ext.Path)"
        }
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
