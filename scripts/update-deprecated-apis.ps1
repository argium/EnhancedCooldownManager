<#
.SYNOPSIS
    Regenerates docs/BlizzardDeprecatedApis.md from Blizzard's deprecated-API source for a given client version.
.DESCRIPTION
    Discovers every Blizzard_Deprecated* addon folder in the Gethe/wow-ui-source mirror at the requested
    tag, downloads each deprecation Lua file, and extracts the public symbols (global functions, namespaced
    or mixin functions, constants, aliases, and mixin tables) that the shims still expose. The symbols are
    grouped per source folder and written as a Markdown denylist.

    Extraction is scope-aware: it ignores anything inside a function body, table literal, or block comment,
    so only the top-level deprecated definitions are captured. This is a destructive write to the output
    file and supports -WhatIf/-Confirm.
.PARAMETER Tag
    The wow-ui-source tag to read, for example 12.0.7.
.PARAMETER OutputPath
    Path to the Markdown file to write. Defaults to docs/BlizzardDeprecatedApis.md next to this script's repo.
.PARAMETER Repo
    The GitHub owner/name mirror to read from. Defaults to Gethe/wow-ui-source.
.PARAMETER Token
    Optional GitHub token for the tree API call. Defaults to the GITHUB_TOKEN environment variable. Only the
    single tree listing hits the rate-limited API; file contents are fetched from raw.githubusercontent.com.
.EXAMPLE
    ./update-deprecated-apis.ps1 -Tag 12.0.7
    Rewrites docs/BlizzardDeprecatedApis.md for patch 12.0.7.
.EXAMPLE
    ./update-deprecated-apis.ps1 -Tag 12.0.7 -WhatIf
    Reports the file that would be written without changing it.
.OUTPUTS
    None. Writes the Markdown denylist to OutputPath.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Tag,

    [string]$OutputPath,

    [string]$Repo = 'Gethe/wow-ui-source',

    [string]$Token = $env:GITHUB_TOKEN
)

Set-StrictMode -Version Latest
Set-PSDebug -Strict
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot 'docs/BlizzardDeprecatedApis.md'
}

$LuaKeywords = @(
    'return', 'end', 'local', 'if', 'then', 'else', 'elseif', 'for', 'while',
    'do', 'repeat', 'until', 'function', 'and', 'or', 'not', 'in', 'break',
    'true', 'false', 'nil'
)

function Get-DeprecatedSymbol {
    <#
    .SYNOPSIS
        Extracts top-level deprecated symbol names from one deprecation Lua file.
    .OUTPUTS
        System.String[] of symbol names in source order, de-duplicated.
    #>
    param([Parameter(Mandatory)][string]$Text)

    $ordered = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $stack = [System.Collections.Generic.List[string]]::new()
    $braceDepth = 0
    $inBlockComment = $false

    foreach ($raw in ($Text -split "\r?\n")) {
        $s = $raw.Trim()

        if ($inBlockComment) {
            if ($s -match '\]\]') { $inBlockComment = $false }
            continue
        }
        if ($s.StartsWith('--[[')) {
            if ($s -notmatch '\]\]') { $inBlockComment = $true }
            continue
        }
        if ($s -eq '' -or $s.StartsWith('--')) { continue }

        $commentIndex = $s.IndexOf('--')
        $code = if ($commentIndex -ge 0) { $s.Substring(0, $commentIndex).TrimEnd() } else { $s }

        $inFunction = $stack.Contains('function')

        if ($braceDepth -eq 0 -and -not $inFunction) {
            if ($code -match '^function\s+([A-Za-z_][\w]*(?:[.:][A-Za-z_][\w]*)*)\s*\(') {
                if ($seen.Add($Matches[1])) { $ordered.Add($Matches[1]) }
            }
            elseif (-not $code.StartsWith('local') -and
                    $code -match '^([A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)*)\s*=(?!=)') {
                $name = $Matches[1]
                $base = ($name -split '[.:]')[0]
                if ($LuaKeywords -notcontains $base -and $seen.Add($name)) { $ordered.Add($name) }
            }
        }

        # Track block scope so function bodies are skipped. A `function` keyword anywhere on the
        # line opens a body (covers `Name = function(...)`); block keywords open matching `end`s.
        if ($code -match '(^|[^\w.:])function\b') {
            $stack.Add('function')
        }
        elseif ($code -match '^([A-Za-z_]\w*)') {
            $first = $Matches[1]
            if (@('if', 'for', 'while', 'do') -contains $first) { $stack.Add($first) }
            elseif ($first -eq 'repeat') { $stack.Add('repeat') }
        }
        if ($code -match '^([A-Za-z_]\w*)') {
            $first = $Matches[1]
            if ((@('end', 'until') -contains $first) -and $stack.Count -gt 0) {
                $stack.RemoveAt($stack.Count - 1)
            }
        }

        $braceDepth += ([regex]::Matches($code, '\{')).Count - ([regex]::Matches($code, '\}')).Count
        if ($braceDepth -lt 0) { $braceDepth = 0 }
    }

    return , $ordered.ToArray()
}

function Format-SymbolLine {
    param([string]$Label, [string[]]$Names)
    $joined = ($Names | ForEach-Object { "``$_``" }) -join ', '
    if ($Label) { "- ${Label}: $joined" } else { "- $joined" }
}

Write-Verbose "Listing deprecated folders in $Repo at $Tag."
$treeUri = "https://api.github.com/repos/$Repo/git/trees/${Tag}?recursive=1"
$headers = @{ 'Accept' = 'application/vnd.github+json'; 'User-Agent' = 'ecm-update-deprecated-apis' }
if ($Token) { $headers['Authorization'] = "Bearer $Token" }
$tree = Invoke-RestMethod -Uri $treeUri -Headers $headers

$files = $tree.tree |
    Where-Object { $_.path -match 'Interface/AddOns/(Blizzard_Deprecated[^/]*)/.*\.lua$' } |
    Where-Object { $_.path -notmatch 'TransitionGuide' } |
    ForEach-Object {
        [void]($_.path -match 'Interface/AddOns/(Blizzard_Deprecated[^/]*)/')
        [pscustomobject]@{ Heading = $Matches[1]; Path = $_.path }
    } |
    Sort-Object Heading, Path

if (-not $files) { throw "No Blizzard_Deprecated* files found at tag $Tag." }

$sections = [ordered]@{}
foreach ($file in $files) {
    $rawUri = "https://raw.githubusercontent.com/$Repo/$Tag/$($file.Path)"
    Write-Verbose "Reading $($file.Path)."
    $content = Invoke-RestMethod -Uri $rawUri -Headers @{ 'User-Agent' = 'ecm-update-deprecated-apis' }
    if ($content -isnot [string]) { $content = [string]$content }

    if (-not $sections.Contains($file.Heading)) {
        $sections[$file.Heading] = [System.Collections.Generic.List[string]]::new()
    }
    foreach ($symbol in (Get-DeprecatedSymbol -Text $content)) {
        if (-not $sections[$file.Heading].Contains($symbol)) { $sections[$file.Heading].Add($symbol) }
    }
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# Deprecated Blizzard APIs ($Tag)")
$lines.Add('')
$lines.Add('Do not use the functions, constants, aliases, or mixins listed below. They are backward-compatibility shims and may be removed. Use the modern replacement shown in Blizzard source, typically a `C_*` namespace method or mixin method:')
$lines.Add('')
$lines.Add("https://github.com/$Repo/tree/$Tag/Interface/AddOns")
$lines.Add('')
$lines.Add('Check the `Blizzard_Deprecated*` folders when choosing the replacement.')
$lines.Add('')

foreach ($heading in $sections.Keys) {
    $symbols = $sections[$heading]
    if ($symbols.Count -eq 0) { continue }

    $constants = [System.Collections.Generic.List[string]]::new()
    $functions = [System.Collections.Generic.List[string]]::new()
    $mixins = [System.Collections.Generic.List[string]]::new()
    foreach ($symbol in $symbols) {
        if ($symbol -match ':') { continue }        # methods of a deprecated mixin table
        elseif ($symbol -match 'Mixin$') { $mixins.Add($symbol) }
        elseif ($symbol -cmatch '^[A-Z][A-Z0-9_]*$') { $constants.Add($symbol) }
        else { $functions.Add($symbol) }
    }

    $lines.Add("## $heading")
    $lines.Add('')
    $categories = @($functions, $constants, $mixins | Where-Object { $_.Count -gt 0 })
    if ($categories.Count -le 1) {
        $flat = @($functions) + @($constants) + @($mixins)
        $lines.Add((Format-SymbolLine -Label '' -Names $flat))
    }
    else {
        if ($functions.Count) { $lines.Add((Format-SymbolLine -Label 'Functions' -Names $functions)) }
        if ($constants.Count) { $lines.Add((Format-SymbolLine -Label 'Constants' -Names $constants)) }
        if ($mixins.Count) { $lines.Add((Format-SymbolLine -Label 'Mixins' -Names $mixins)) }
    }
    $lines.Add('')
}

$markdown = ($lines -join "`n").TrimEnd() + "`n"

if ($PSCmdlet.ShouldProcess($OutputPath, 'Write deprecated-API denylist')) {
    Set-Content -Path $OutputPath -Value $markdown -Encoding utf8 -NoNewline
    Write-Verbose "Wrote $($sections.Keys.Count) sections to $OutputPath."
}
