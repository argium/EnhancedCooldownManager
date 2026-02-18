param(
    [string]$TocPath = "EnhancedCooldownManager.toc",
    [string]$Remote = "origin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path -LiteralPath $TocPath)) {
    throw "TOC file not found: $TocPath"
}

$versionMatch = Select-String -Path $TocPath -Pattern '^\s*##\s*Version:\s*(.+?)\s*$' | Select-Object -First 1
if (-not $versionMatch) {
    throw "Could not find a '## Version:' line in $TocPath"
}

$version = $versionMatch.Matches[0].Groups[1].Value.Trim()
if ([string]::IsNullOrWhiteSpace($version)) {
    throw "Parsed an empty version from $TocPath"
}

Write-Host "TOC version: $version"

Invoke-Git -Arguments @("rev-parse", "--is-inside-work-tree")

& git show-ref --verify --quiet "refs/tags/$version"
$localTagExists = $LASTEXITCODE -eq 0
if (-not $localTagExists -and $LASTEXITCODE -ne 1) {
    throw "Failed checking local tag existence for '$version'."
}

$remoteQuery = & git ls-remote --tags --refs $Remote "refs/tags/$version" 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Failed querying remote '$Remote' for tag '$version': $($remoteQuery -join "`n")"
}
$remoteTagExists = -not [string]::IsNullOrWhiteSpace(($remoteQuery -join "`n"))

if (-not $localTagExists -and -not $remoteTagExists) {
    Write-Host "Creating local tag '$version'"
    Invoke-Git -Arguments @("tag", $version)
    $localTagExists = $true
} elseif ($localTagExists) {
    Write-Host "Local tag '$version' already exists." -ForegroundColor Yellow
} else {
    Write-Host "Tag '$version' already exists on remote '$Remote'." -ForegroundColor Yellow
}

if ($remoteTagExists) {
    Write-Host "Refusing to push because '$version' already exists on '$Remote'." -ForegroundColor Red
    exit 0
}

if (-not $localTagExists) {
    throw "Cannot push '$version' because no local tag was found."
}

Write-Host "Pushing tag '$version' to '$Remote'"
Invoke-Git -Arguments @("push", $Remote, "refs/tags/$version")
Write-Host "Done." -ForegroundColor Green
