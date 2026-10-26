#Requires -Version 5.1
<#
.SYNOPSIS
    Builds catalog/catalog.json from the Spicetify Marketplace's public sources.

.DESCRIPTION
    The Marketplace does not ship a static catalog: it queries GitHub for repositories
    tagged with topic:spicetify-extensions / spicetify-themes / spicetify-apps and then
    reads each repository's manifest.json. This script does the same thing once, offline,
    so the repository has a reproducible inventory of every listed plugin.

    Output files (all committed, so a normal user never has to run this):
      catalog/catalog.json   - normalized extensions, themes and apps
      catalog/snippets.json  - the Marketplace CSS snippet collection
      catalog/blacklist.json - blacklist snapshot used while syncing
      catalog/errors.json    - repositories whose manifest could not be read

.PARAMETER OutDir
    Destination directory. Defaults to <repo>/catalog.

.PARAMETER MaxPages
    Maximum GitHub search pages per topic (100 repositories per page).

.PARAMETER Throttle
    Number of manifest downloads kept in flight at once.

.PARAMETER IncludeArchived
    Keep archived repositories in the catalog. They are excluded by default.

.PARAMETER Token
    GitHub token. Defaults to GITHUB_TOKEN, then to `gh auth token`.

.EXAMPLE
    pwsh ./tools/Sync-Catalog.ps1 -Verbose
#>
[CmdletBinding()]
param(
    [string] $OutDir = '',
    [int]    $MaxPages = 10,
    [int]    $Throttle = 12,
    [switch] $IncludeArchived,
    [string] $Token = $env:GITHUB_TOKEN
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11

if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot '..\catalog' }
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Topics = @{
    extensions = 'spicetify-extensions'
    themes     = 'spicetify-themes'
    apps       = 'spicetify-apps'
}
$MarketplaceRaw = 'https://raw.githubusercontent.com/spicetify/marketplace/main'
$UserAgent = 'spotify-debloat-catalog/1.0 (+https://github.com/sinnerk/spotify-debloat)'

# --------------------------------------------------------------------------- helpers

function Get-GitHubToken {
    param([string] $Explicit)
    if ($Explicit) { return $Explicit }
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        $candidate = Join-Path ${env:ProgramFiles} 'GitHub CLI\gh.exe'
        if (Test-Path -LiteralPath $candidate) { $gh = Get-Item -LiteralPath $candidate }
    }
    if ($gh) {
        try { return (& $gh.Source auth token 2>$null | Select-Object -First 1) } catch { }
    }
    return $null
}

function New-HttpClient {
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd($UserAgent)
    $client.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.github+json')
    $client.Timeout = [TimeSpan]::FromSeconds(45)
    return $client
}

function Invoke-GitHubSearch {
    param(
        [System.Net.Http.HttpClient] $Client,
        [string] $Topic,
        [string] $AuthToken
    )

    $results = New-Object System.Collections.ArrayList
    for ($page = 1; $page -le $MaxPages; $page++) {
        $uri = 'https://api.github.com/search/repositories?q=' + [Uri]::EscapeDataString("topic:$Topic") +
               "&sort=stars&order=desc&per_page=100&page=$page"
        $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $uri)
        if ($AuthToken) { $request.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $AuthToken) }

        $response = $Client.SendAsync($request).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "GitHub search failed for '$Topic' page ${page}: $($response.StatusCode) $body"
        }

        $parsed = $body | ConvertFrom-Json
        if (-not $parsed.items -or $parsed.items.Count -eq 0) { break }
        foreach ($item in $parsed.items) { [void] $results.Add($item) }

        Write-Verbose ("{0}: page {1}, {2}/{3} repositories" -f $Topic, $page, $results.Count, $parsed.total_count)
        if ($results.Count -ge $parsed.total_count) { break }
        Start-Sleep -Milliseconds 700
    }
    return $results
}

function ConvertTo-GlobRegex {
    param([string] $Pattern)
    return '^' + ([Regex]::Escape($Pattern).Replace('\*', '.*')) + '$'
}

function Test-Blacklisted {
    param([string] $Url, [string[]] $Patterns)
    foreach ($pattern in $Patterns) {
        if ($pattern.StartsWith('//')) { continue }
        if ($Url -match (ConvertTo-GlobRegex $pattern)) { return $true }
    }
    return $false
}

function Resolve-RepoUrl {
    param([string] $RepoUrl, [string] $Branch, [string] $Path)
    if (-not $Path) { return $null }
    if ($Path -match '^https?://') { return $Path }
    $clean = $Path -replace '^\./', ''
    $encoded = ($clean -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    return "https://raw.githubusercontent.com/$RepoUrl/$Branch/$encoded"
}

function Get-Slug {
    param([string] $Value)
    $slug = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    return $slug.Trim('-')
}

function Get-Utf8Text {
    param(
        [System.Net.Http.HttpClient] $Client,
        [string] $Url
    )
    $response = $Client.GetAsync($Url).GetAwaiter().GetResult()
    if (-not $response.IsSuccessStatusCode) {
        throw "Request failed ($($response.StatusCode)): $Url"
    }
    $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
    $response.Dispose()
    return [Text.Encoding]::UTF8.GetString($bytes)
}

function Invoke-TextBatch {
    param(
        [System.Net.Http.HttpClient] $Client,
        [string[]] $Urls,
        [int] $BatchSize
    )

    $map = @{}
    $list = @($Urls | Select-Object -Unique)
    for ($offset = 0; $offset -lt $list.Count; $offset += $BatchSize) {
        $end = [Math]::Min($offset + $BatchSize - 1, $list.Count - 1)
        $batch = $list[$offset..$end]
        $tasks = @{}
        foreach ($url in $batch) {
            $tasks[$url] = $Client.GetAsync($url)
        }
        foreach ($url in $batch) {
            $task = $tasks[$url]
            try {
                $null = $task.Wait(60000)
                if ($task.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                    $response = $task.Result
                    if ($response.IsSuccessStatusCode) {
                        $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
                        $map[$url] = [Text.Encoding]::UTF8.GetString($bytes)
                    } else {
                        $map[$url] = $null
                    }
                    $response.Dispose()
                } else {
                    $map[$url] = $null
                }
            } catch {
                $map[$url] = $null
            }
        }
        Write-Verbose ("manifests: {0}/{1}" -f $end, ($list.Count - 1))
    }
    return $map
}

# --------------------------------------------------------------------------- main

$client = New-HttpClient
$auth = Get-GitHubToken -Explicit $Token
if (-not $auth) { Write-Warning 'No GitHub token found. Search is limited to 10 requests/minute.' }

$blacklistPath = Join-Path $OutDir 'blacklist.json'
if (Test-Path -LiteralPath $blacklistPath) {
    $blacklist = (Get-Content -LiteralPath $blacklistPath -Raw | ConvertFrom-Json).repos
} else {
    $blacklist = (Get-Utf8Text -Client $client -Url "$MarketplaceRaw/resources/blacklist.json" | ConvertFrom-Json).repos
}
$blacklist = @($blacklist)

$repos = @{}
foreach ($kind in $Topics.Keys) {
    $repos[$kind] = Invoke-GitHubSearch -Client $client -Topic $Topics[$kind] -AuthToken $auth
    Write-Host ("[{0}] {1} repositories" -f $kind, $repos[$kind].Count)
}

# --- extension + app manifests -------------------------------------------------------
$manifestTargets = New-Object System.Collections.ArrayList
foreach ($kind in @('extensions', 'apps')) {
    foreach ($repo in $repos[$kind]) {
        if (-not $IncludeArchived -and $repo.archived) { continue }
        if (Test-Blacklisted -Url $repo.html_url -Patterns $blacklist) { continue }
        $branch = if ($repo.default_branch) { $repo.default_branch } else { 'main' }
        $url = "https://raw.githubusercontent.com/$($repo.full_name)/$branch/manifest.json"
        [void] $manifestTargets.Add([pscustomobject]@{
            Kind   = $kind
            Repo   = $repo
            Branch = $branch
            Url    = $url
        })
    }
}

$manifestText = Invoke-TextBatch -Client $client -Urls ($manifestTargets.Url) -BatchSize $Throttle
$extensions = New-Object System.Collections.ArrayList
$apps = New-Object System.Collections.ArrayList
$errors = New-Object System.Collections.ArrayList
$seenIds = @{}

foreach ($target in $manifestTargets) {
    $repo = $target.Repo
    $text = $manifestText[$target.Url]
    if (-not $text) {
        [void] $errors.Add([pscustomobject]@{ repo = $repo.full_name; kind = $target.Kind; reason = 'manifest-unavailable' })
        continue
    }

    try { $parsed = $text | ConvertFrom-Json } catch {
        [void] $errors.Add([pscustomobject]@{ repo = $repo.full_name; kind = $target.Kind; reason = 'manifest-invalid-json' })
        continue
    }

    $items = if ($parsed.PSObject.Properties['value']) { @($parsed.value) } else { @($parsed) }
    if (-not $items -or $items.Count -eq 0) {
        [void] $errors.Add([pscustomobject]@{ repo = $repo.full_name; kind = $target.Kind; reason = 'manifest-empty' })
        continue
    }

    $index = 0
    foreach ($item in $items) {
        $index++
        if (-not $item.name -or -not $item.main) { continue }

        $main = [string] $item.main
        $mainLeaf = ($main -split '[\\/]')[-1]
        $mainLeaf = ($mainLeaf -replace '[<>:"|?*]', '')
        $mainStem = $mainLeaf -replace '\.[^.]*$', ''
        $id = '{0}--{1}' -f (Get-Slug $repo.full_name), (Get-Slug $mainStem)
        if ($seenIds.ContainsKey($id)) {
            $seenIds[$id]++
            $id = "$id-$($seenIds[$id])"
        } else {
            $seenIds[$id] = 1
        }

        $tags = @()
        if ($item.tags) { $tags = @($item.tags | ForEach-Object { [string] $_ } | Where-Object { $_ }) }

        $authors = @()
        if ($item.authors) {
            foreach ($author in @($item.authors)) {
                if ($author -is [string]) { $authors += [pscustomobject]@{ name = $author; url = $null } }
                elseif ($author.name) { $authors += [pscustomobject]@{ name = [string] $author.name; url = [string] $author.url } }
            }
        }
        if ($authors.Count -eq 0) {
            $authors = @([pscustomobject]@{ name = ($repo.full_name -split '/')[0]; url = $repo.html_url })
        }

        $description = if ($item.description) { [string] $item.description } else { [string] $repo.description }
        if ($description.Length -gt 320) { $description = $description.Substring(0, 317) + '...' }

        $branch = if ($item.branch) { [string] $item.branch } else { $target.Branch }
        $entry = [pscustomobject]@{
            id          = $id
            name        = [string] $item.name
            description = $description
            repo        = $repo.full_name
            repoUrl     = $repo.html_url
            branch      = $branch
            main        = $main
            rawUrl      = (Resolve-RepoUrl -RepoUrl $repo.full_name -Branch $branch -Path $main)
            previewUrl  = (Resolve-RepoUrl -RepoUrl $repo.full_name -Branch $branch -Path $item.preview)
            authors     = $authors
            tags        = $tags
            stars       = [int] $repo.stargazers_count
            pushedAt    = [string] $repo.pushed_at
            archived    = [bool] $repo.archived
        }

        if ($target.Kind -eq 'extensions') { [void] $extensions.Add($entry) }
        else { [void] $apps.Add($entry) }
    }
}

# The Marketplace sometimes lists the same file twice (for example a repo with an
# English and a translated manifest entry). Two entries would download identical
# code under two names, so keep the first after sorting and drop the rest.
function Remove-DuplicateRawUrl {
    param($Entries)
    $seen = @{}
    $unique = New-Object System.Collections.ArrayList
    foreach ($entry in $Entries) {
        if ($seen.ContainsKey($entry.rawUrl)) { continue }
        $seen[$entry.rawUrl] = $true
        [void] $unique.Add($entry)
    }
    return $unique
}

# --- themes --------------------------------------------------------------------------
$themes = New-Object System.Collections.ArrayList
foreach ($repo in $repos['themes']) {
    if (-not $IncludeArchived -and $repo.archived) { continue }
    if (Test-Blacklisted -Url $repo.html_url -Patterns $blacklist) { continue }

    $name = ($repo.name -replace '[-_]+', ' ')
    $themes.Add([pscustomobject]@{
        id          = Get-Slug $repo.full_name
        name        = $name
        description = if ($repo.description) { [string] $repo.description } else { '' }
        repo        = $repo.full_name
        repoUrl     = $repo.html_url
        branch      = if ($repo.default_branch) { $repo.default_branch } else { 'main' }
        stars       = [int] $repo.stargazers_count
        pushedAt    = [string] $repo.pushed_at
        archived    = [bool] $repo.archived
    }) | Out-Null
}

# --- snippets ------------------------------------------------------------------------
$snippetsRaw = Get-Utf8Text -Client $client -Url "$MarketplaceRaw/resources/snippets.json" | ConvertFrom-Json
$snippets = New-Object System.Collections.ArrayList
foreach ($snippet in @($snippetsRaw)) {
    if (-not $snippet.title -or -not $snippet.code) { continue }
    [void] $snippets.Add([pscustomobject]@{
        id          = Get-Slug $snippet.title
        title       = [string] $snippet.title
        description = [string] $snippet.description
        code        = [string] $snippet.code
        preview     = [string] $snippet.preview
        source      = "$MarketplaceRaw/resources/snippets.json"
    })
}

# --- write ---------------------------------------------------------------------------
$extensionList = @(Remove-DuplicateRawUrl ($extensions | Sort-Object -Property @{ Expression = 'stars'; Descending = $true }, name))
$themeList     = @($themes | Sort-Object -Property @{ Expression = 'stars'; Descending = $true }, name)
$appList       = @(Remove-DuplicateRawUrl ($apps | Sort-Object -Property @{ Expression = 'stars'; Descending = $true }, name))

$catalog = [ordered]@{
    schemaVersion = 1
    generatedAt   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    source        = [ordered]@{
        marketplace = 'https://github.com/spicetify/marketplace'
        topics      = $Topics
        blacklist   = "$MarketplaceRaw/resources/blacklist.json"
        snippets    = "$MarketplaceRaw/resources/snippets.json"
    }
    counts        = [ordered]@{
        extensions = $extensionList.Count
        themes     = $themeList.Count
        apps       = $appList.Count
        snippets   = $snippets.Count
        errors     = $errors.Count
    }
    extensions    = $extensionList
    themes        = $themeList
    apps          = $appList
}

$catalogJson = $catalog | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText((Join-Path $OutDir 'catalog.json'), $catalogJson, (New-Object System.Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $OutDir 'snippets.json'), (ConvertTo-Json @($snippets) -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $OutDir 'blacklist.json'), (ConvertTo-Json ([ordered]@{ repos = $blacklist }) -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $OutDir 'errors.json'), (ConvertTo-Json ([ordered]@{ generatedAt = $catalog.generatedAt; errors = @($errors) }) -Depth 4), (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host ("Catalog written to {0}" -f $OutDir)
Write-Host ("  extensions {0}  themes {1}  apps {2}  snippets {3}  errors {4}" -f `
    $extensionList.Count, $themeList.Count, $appList.Count, $snippets.Count, $errors.Count)
