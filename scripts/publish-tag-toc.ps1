param(
    [string]$TocPath = "EnhancedCooldownManager.toc",
    [string]$Remote = "origin",
    [Alias("TagMessage", "ReleaseMessage")]
    [string]$Message,
    [switch]$ShowReleasePopup
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($Message)) {
    throw "A non-empty -Message is required. The release tag annotation is used for the GitHub release and published changelog."
}

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

function Get-GitTagTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TagName
    )

    $tagTargetOutput = & git rev-parse "refs/tags/$TagName^{}" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed resolving target for tag '$TagName': $($tagTargetOutput -join "`n")"
    }

    return ($tagTargetOutput | Select-Object -First 1).ToString().Trim()
}

function Get-GitHubWorkflowsUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteName
    )

    $remoteUrlOutput = & git remote get-url $RemoteName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Could not resolve remote '$RemoteName' URL; skipping browser open." -ForegroundColor Yellow
        return $null
    }

    $remoteUrl = ($remoteUrlOutput | Select-Object -First 1).ToString().Trim()
    if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
        Write-Host "Remote '$RemoteName' returned an empty URL; skipping browser open." -ForegroundColor Yellow
        return $null
    }

    $repoPath = $null
    if ($remoteUrl -match '^https?://github\.com/(?<repo>[^/]+/[^/]+?)(?:\.git)?/?$') {
        $repoPath = $Matches['repo']
    } elseif ($remoteUrl -match '^git@github\.com:(?<repo>[^/]+/[^/]+?)(?:\.git)?$') {
        $repoPath = $Matches['repo']
    } elseif ($remoteUrl -match '^ssh://git@github\.com/(?<repo>[^/]+/[^/]+?)(?:\.git)?/?$') {
        $repoPath = $Matches['repo']
    }

    if (-not $repoPath) {
        Write-Host "Remote '$RemoteName' is not a supported GitHub URL ('$remoteUrl'); skipping browser open." -ForegroundColor Yellow
        return $null
    }

    return "https://github.com/$repoPath/actions"
}

function Open-GitHubWorkflowsPage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteName
    )

    $workflowsUrl = Get-GitHubWorkflowsUrl -RemoteName $RemoteName
    if (-not $workflowsUrl) {
        return
    }

    Write-Host "Opening workflows page: $workflowsUrl"
    try {
        Start-Process $workflowsUrl | Out-Null
    } catch {
        Write-Host "Failed to open browser for workflows page: $($_.Exception.Message)" -ForegroundColor Yellow
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

function Set-ReleasePopupVersion {
    param(
        [Parameter(Mandatory)]
        [string]$Version,
        [string]$ConstantsPath = "ECM_Constants.lua"
    )

    if (-not (Test-Path -LiteralPath $ConstantsPath)) {
        throw "Constants file not found: $ConstantsPath"
    }

    $content = Get-Content -LiteralPath $ConstantsPath -Raw
    $pattern = '(RELEASE_POPUP_VERSION\s*=\s*")[^"]*(")'
    if ($content -notmatch 'RELEASE_POPUP_VERSION') {
        throw "Could not find RELEASE_POPUP_VERSION in $ConstantsPath"
    }

    $newContent = $content -replace $pattern, "`${1}$Version`${2}"
    if ($newContent -eq $content) {
        Write-Host "RELEASE_POPUP_VERSION is already '$Version' in $ConstantsPath"
        return $false
    }

    Set-Content -LiteralPath $ConstantsPath -Value $newContent -NoNewline
    Write-Host "Updated RELEASE_POPUP_VERSION to '$Version' in $ConstantsPath"
    return $true
}

if ($ShowReleasePopup) {
    $releasePopupVersionChanged = Set-ReleasePopupVersion -Version $version
    if ($releasePopupVersionChanged) {
        Invoke-Git -Arguments @("add", "ECM_Constants.lua")
        Invoke-Git -Arguments @("commit", "-m", "Set release popup version to $version")
    }
}

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

if ($remoteTagExists) {
    throw "Tag '$version' already exists on '$Remote'. Its release notes are already locked in. Delete the remote tag/release manually or bump the version before publishing again."
}

if (-not $localTagExists) {
    Write-Host "Creating local tag '$version'"
    Write-Host "Using tag/release message: $Message"
    Invoke-Git -Arguments @("tag", "-a", $version, "-m", $Message)
    $localTagExists = $true
} else {
    Write-Host "Local tag '$version' already exists." -ForegroundColor Yellow

    $tagTarget = Get-GitTagTarget -TagName $version
    Write-Host "Replacing local tag '$version' so it exactly matches the provided release message before pushing."
    Invoke-Git -Arguments @("tag", "-d", $version)
    Write-Host "Using tag/release message: $Message"
    Invoke-Git -Arguments @("tag", "-a", $version, "-m", $Message, $tagTarget)
}

if (-not $localTagExists) {
    throw "Cannot push '$version' because no local tag was found."
}

Write-Host "Pushing tag '$version' to '$Remote'"
Invoke-Git -Arguments @("push", $Remote, "refs/tags/$version")
Write-Host "Done." -ForegroundColor Green
Open-GitHubWorkflowsPage -RemoteName $Remote
