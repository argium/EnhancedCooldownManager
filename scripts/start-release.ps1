param(
    [string]$TocPath = "EnhancedCooldownManager.toc",
    [string]$Remote = "origin",
    [string]$Message,
    [string]$MessagePath,
    [switch]$ShowReleasePopup,
    [switch]$DryRun
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

function Invoke-Gh {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & gh @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "gh $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Get-GitOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & git @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output -join "`n")"
    }

    return ($output | Select-Object -First 1).ToString().Trim()
}

function Test-GitRefExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Ref
    )

    & git show-ref --verify --quiet $Ref
    if ($LASTEXITCODE -eq 0) {
        return $true
    }

    if ($LASTEXITCODE -eq 1) {
        return $false
    }

    throw "Failed checking git ref '$Ref'."
}

function Get-RemoteTagTarget {
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    $remoteQuery = & git ls-remote --tags $Remote "refs/tags/$Version" "refs/tags/$Version^{}" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed querying remote '$Remote' for tag '$Version': $($remoteQuery -join "`n")"
    }

    $lines = @($remoteQuery | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -eq 0) {
        return $null
    }

    $peeledRef = "refs/tags/$Version^{}"
    foreach ($line in $lines) {
        $parts = $line -split "\s+"
        if ($parts.Count -ge 2 -and $parts[1] -eq $peeledRef) {
            return $parts[0]
        }
    }

    $tagRef = "refs/tags/$Version"
    foreach ($line in $lines) {
        $parts = $line -split "\s+"
        if ($parts.Count -ge 2 -and $parts[1] -eq $tagRef) {
            return $parts[0]
        }
    }

    throw "Could not parse remote tag '$Version' from '$Remote': $($remoteQuery -join "`n")"
}

function Get-ReleaseMessage {
    if (-not [string]::IsNullOrWhiteSpace($Message) -and -not [string]::IsNullOrWhiteSpace($MessagePath)) {
        throw "Use either -Message or -MessagePath, not both."
    }

    if (-not [string]::IsNullOrWhiteSpace($MessagePath)) {
        if (-not (Test-Path -LiteralPath $MessagePath)) {
            throw "Release message file not found: $MessagePath"
        }

        return Get-Content -LiteralPath $MessagePath -Raw
    }

    return $Message
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
        $repoPath = $Matches["repo"]
    } elseif ($remoteUrl -match '^git@github\.com:(?<repo>[^/]+/[^/]+?)(?:\.git)?$') {
        $repoPath = $Matches["repo"]
    } elseif ($remoteUrl -match '^ssh://git@github\.com/(?<repo>[^/]+/[^/]+?)(?:\.git)?/?$') {
        $repoPath = $Matches["repo"]
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

function Set-ReleasePopupVersion {
    param(
        [Parameter(Mandatory)]
        [string]$Version,
        [string]$ConstantsPath = "Constants.lua"
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

    if ($DryRun) {
        Write-Host "Dry run: would update RELEASE_POPUP_VERSION to '$Version' in $ConstantsPath"
        return $false
    }

    Set-Content -LiteralPath $ConstantsPath -Value $newContent -NoNewline
    Write-Host "Updated RELEASE_POPUP_VERSION to '$Version' in $ConstantsPath"
    return $true
}

function Assert-RemoteReleaseAvailable {
    param(
        [Parameter(Mandatory)]
        [string]$Version,
        [Parameter(Mandatory)]
        [string]$Commit
    )

    $remoteTarget = Get-RemoteTagTarget -Version $Version
    if ($remoteTarget) {
        if ($remoteTarget -ne $Commit) {
            throw "Tag '$Version' already exists on '$Remote' but points to '$remoteTarget', not '$Commit'. Bump the TOC version before publishing again."
        }

        Write-Host "Remote tag '$Version' already points at this commit; release dispatch can retry."
    }

    $releaseQuery = & gh release view $Version --json tagName 2>&1
    if ($LASTEXITCODE -eq 0) {
        throw "GitHub Release '$Version' already exists. Bump the TOC version before publishing again."
    }

    if (($releaseQuery -join "`n") -notmatch '(?i)not found') {
        throw "Failed checking GitHub Release '$Version': $($releaseQuery -join "`n")"
    }
}

function Get-TocVersionFromContent {
    param(
        [Parameter(Mandatory)]
        [string]$Content,
        [Parameter(Mandatory)]
        [string]$Source
    )

    $match = [regex]::Match($Content, '(?m)^\s*##\s*Version:\s*(.+?)\s*$')
    if (-not $match.Success) {
        throw "Could not find a '## Version:' line in $Source"
    }

    $version = $match.Groups[1].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "Parsed an empty version from $Source"
    }

    return $version
}

function Get-CommittedTocVersion {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $gitPath = $Path -replace '\\', '/'
    $content = & git show "HEAD:$gitPath" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read committed TOC file from HEAD: $($content -join "`n")"
    }

    return Get-TocVersionFromContent -Content ($content -join "`n") -Source "HEAD:$Path"
}

function Sync-ReleaseBranch {
    param(
        [Parameter(Mandatory)]
        [string]$BranchName
    )

    if ($DryRun) {
        $remoteQuery = & git ls-remote --heads $Remote "refs/heads/$BranchName" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed querying remote '$Remote' for branch '$BranchName': $($remoteQuery -join "`n")"
        }

        if ([string]::IsNullOrWhiteSpace(($remoteQuery -join "`n"))) {
            throw "Remote branch '$Remote/$BranchName' was not found. Push the branch before dispatching a release."
        }

        Write-Host "Dry run: would fetch '$BranchName', verify branch history, and push only local-ahead commits."
        return
    }

    Write-Host "Fetching '$BranchName' from '$Remote'"
    Invoke-Git -Arguments @("fetch", $Remote, $BranchName)

    $remoteRef = "refs/remotes/$Remote/$BranchName"
    if (-not (Test-GitRefExists -Ref $remoteRef)) {
        throw "Remote branch '$Remote/$BranchName' was not found. Push the branch before dispatching a release."
    }

    $localCommit = Get-GitOutput -Arguments @("rev-parse", "HEAD")
    $remoteCommit = Get-GitOutput -Arguments @("rev-parse", $remoteRef)
    $mergeBase = Get-GitOutput -Arguments @("merge-base", "HEAD", $remoteRef)

    if ($localCommit -eq $remoteCommit) {
        Write-Host "Branch '$BranchName' is already pushed."
        return
    }

    if ($mergeBase -eq $remoteCommit) {
        Write-Host "Pushing '$BranchName' to '$Remote'"
        Invoke-Git -Arguments @("push", $Remote, "HEAD:refs/heads/$BranchName")
        return
    }

    if ($mergeBase -eq $localCommit) {
        throw "Local branch '$BranchName' is behind '$Remote/$BranchName'. Pull or rebase before releasing."
    }

    throw "Local branch '$BranchName' has diverged from '$Remote/$BranchName'. Resolve the branch history before releasing."
}

if ((Get-GitOutput -Arguments @("rev-parse", "--is-inside-work-tree")) -ne "true") {
    throw "Current directory is not inside a git worktree."
}

if (-not (Test-Path -LiteralPath $TocPath)) {
    throw "TOC file not found: $TocPath"
}

$releaseMessage = Get-ReleaseMessage
if ([string]::IsNullOrWhiteSpace($releaseMessage)) {
    throw "A non-empty -Message or -MessagePath is required. The text is used for the packager changelog and GitHub Release."
}

$version = Get-TocVersionFromContent -Content (Get-Content -LiteralPath $TocPath -Raw) -Source $TocPath
$committedVersion = Get-CommittedTocVersion -Path $TocPath
if ($version -ne $committedVersion) {
    throw "Working-copy TOC version '$version' differs from committed TOC version '$committedVersion'. Commit the TOC version change before dispatching the release."
}

if (-not $version.StartsWith("v")) {
    throw "TOC version '$version' must start with 'v'."
}

Write-Host "TOC version: $version"

$branch = Get-GitOutput -Arguments @("branch", "--show-current")
if ([string]::IsNullOrWhiteSpace($branch)) {
    throw "Releases must be dispatched from a named branch, not detached HEAD."
}

$isPrerelease = $version.Contains("-")
if ($isPrerelease) {
    $versionLower = $version.ToLowerInvariant()
    if (-not $versionLower.Contains("alpha") -and -not $versionLower.Contains("beta")) {
        throw "Prerelease TOC version '$version' must include 'alpha' or 'beta' so external uploads are not marked stable."
    }
}

if (-not $isPrerelease -and $branch -ne "main") {
    throw "Stable releases must come from 'main'. '$version' is a stable version but the current branch is '$branch'."
}

$commit = Get-GitOutput -Arguments @("rev-parse", "HEAD")

Invoke-Gh -Arguments @("auth", "status")

if ($ShowReleasePopup) {
    $releasePopupVersionChanged = Set-ReleasePopupVersion -Version $version
    if ($releasePopupVersionChanged) {
        Invoke-Git -Arguments @("add", "Constants.lua")
        Invoke-Git -Arguments @("commit", "-m", "Set release popup version to $version")
    }
}

Assert-RemoteReleaseAvailable -Version $version -Commit $commit
Sync-ReleaseBranch -BranchName $branch

$inputs = @{ release_notes = $releaseMessage } | ConvertTo-Json -Compress

if ($DryRun) {
    Write-Host "Dry run: would dispatch release.yml for '$version' from '$branch'."
    exit 0
}

Write-Host "Dispatching release.yml for '$version' from '$branch'"
$inputs | gh workflow run release.yml --ref $branch --json
if ($LASTEXITCODE -ne 0) {
    throw "gh workflow run release.yml failed with exit code $LASTEXITCODE."
}

Write-Host "Release workflow dispatched." -ForegroundColor Green
Open-GitHubWorkflowsPage -RemoteName $Remote
