#Requires -Version 5.1
<#
.SYNOPSIS
    Test suite for spotify-debloat.

.DESCRIPTION
    Dependency-free on purpose: no Pester, so it runs on a stock Windows PowerShell 5.1
    and on PowerShell 7 without installing anything. Sections that need a live Spotify
    install are skipped (and reported as SKIP) when it is absent, which is what happens
    on CI runners.

    Exit code 0 when every assertion passed, 1 otherwise.

.PARAMETER Section
    all, json, catalog, presets, policy, module, theme, style, privacy.

.EXAMPLE
    .\tests\Run-Tests.ps1

.EXAMPLE
    .\tests\Run-Tests.ps1 -Section theme
#>
[CmdletBinding()]
param(
    [ValidateSet('all', 'json', 'catalog', 'presets', 'policy', 'module', 'theme', 'style', 'privacy')]
    [string] $Section = 'all'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$script:Root = Split-Path -Parent $PSScriptRoot
$script:Passed = 0
$script:Failed = 0
$script:Skipped = 0
$script:Failures = New-Object System.Collections.ArrayList
$script:CurrentSection = ''
$script:LeanModule = $null

# ---------------------------------------------------------------- harness

function Write-Section {
    param([string] $Name)
    $script:CurrentSection = $Name
    Write-Host ''
    Write-Host ("  {0}" -f $Name) -ForegroundColor Cyan
}

function Add-Pass {
    $script:Passed++
    Write-Host '    ok   ' -NoNewline -ForegroundColor DarkGreen
    Write-Host $args[0] -ForegroundColor DarkGray
}

function Add-Fail {
    param([string] $Message)
    $script:Failed++
    [void] $script:Failures.Add(("{0}: {1}" -f $script:CurrentSection, $Message))
    Write-Host '    FAIL ' -NoNewline -ForegroundColor Red
    Write-Host $Message
}

function Add-Skip {
    param([string] $Message)
    $script:Skipped++
    Write-Host '    skip ' -NoNewline -ForegroundColor DarkYellow
    Write-Host $Message -ForegroundColor DarkGray
}

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if ($Condition) { Add-Pass $Message } else { Add-Fail $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Message)
    if ("$Expected" -eq "$Actual") {
        Add-Pass $Message
    } else {
        Add-Fail ("{0} (expected '{1}', got '{2}')" -f $Message, $Expected, $Actual)
    }
}

function Assert-Match {
    param([string] $Pattern, [string] $Value, [string] $Message)
    if ($Value -and $Value -match $Pattern) {
        Add-Pass $Message
    } else {
        Add-Fail ("{0} (value: '{1}')" -f $Message, $Value)
    }
}

function Get-RepoFiles {
    param([string[]] $Extension)
    $files = @(Get-ChildItem -LiteralPath $script:Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch '\\node_modules\\|\\\.git\\' -and
            ($Extension -contains $_.Extension.ToLowerInvariant())
        })
    return $files
}

function Read-TextFile {
    param([string] $Path)
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

function Test-Node {
    return [bool] (Get-Command node -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------- json

function Invoke-JsonSection {
    Write-Section 'json - every committed JSON file parses'

    $files = @(Get-RepoFiles -Extension @('.json'))
    Assert-True ($files.Count -ge 5) ("found {0} json files" -f $files.Count)

    $bad = New-Object System.Collections.ArrayList
    foreach ($file in $files) {
        try {
            $null = Read-TextFile $file.FullName | ConvertFrom-Json
        } catch {
            [void] $bad.Add($file.FullName.Substring($script:Root.Length).TrimStart('\'))
        }
    }
    Assert-True ($bad.Count -eq 0) ("all json parses ({0} invalid: {1})" -f $bad.Count, ($bad -join ', '))

    $catalog = Read-TextFile (Join-Path $script:Root 'catalog\catalog.json') | ConvertFrom-Json
    Assert-Equal 1 $catalog.schemaVersion 'catalog schemaVersion is 1'
    Assert-Equal $catalog.extensions.Count $catalog.counts.extensions 'catalog extension count matches array'
    Assert-Equal $catalog.themes.Count $catalog.counts.themes 'catalog theme count matches array'
    Assert-Equal $catalog.apps.Count $catalog.counts.apps 'catalog app count matches array'

    $snippets = Read-TextFile (Join-Path $script:Root 'catalog\snippets.json') | ConvertFrom-Json
    Assert-Equal $snippets.Count $catalog.counts.snippets 'catalog snippet count matches array'
    Assert-True ($catalog.extensions.Count -gt 100) 'catalog has a plausible number of extensions'

    foreach ($report in @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'reports') -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        $data = Read-TextFile $report.FullName | ConvertFrom-Json
        Assert-True ($data.memory.workingSetAverageMB -gt 0 -and $data.cpu.percentOfOneCore -ge 0) ("report {0} has measurements" -f $report.Name)
    }
}

# ---------------------------------------------------------------- catalog

function Test-CatalogEntry {
    param($Entry, [string] $Kind, [hashtable] $Seen)

    $label = "{0} {1}" -f $Kind, $Entry.id
    Assert-True ([bool] $Entry.id) ("$label has an id")
    Assert-True ([bool] $Entry.name) ("$label has a name")
    Assert-True ([bool] $Entry.repo) ("$label has a repo")

    if ($Seen.ContainsKey($Entry.id)) {
        Add-Fail ("duplicate $Kind id: {0}" -f $Entry.id)
    } else {
        $Seen[$Entry.id] = $true
    }

    if ($Kind -eq 'extensions') {
        Assert-True ([bool] $Entry.main) ("$label has a main file")
        # Most entries live on raw.githubusercontent.com, but the Marketplace also
        # lists jsDelivr, GitHub Pages and release-asset URLs. Any HTTPS source is
        # fine as long as it serves a script.
        Assert-Match '^https://[^/]+/.+\.(js|mjs|cjs)$' $Entry.rawUrl ("$label raw url is an https script url")
        Assert-Match '^https://github\.com/' $Entry.repoUrl ("$label repo url is https")
        Assert-True ($null -ne $Entry.stars) ("$label has a star count")
    }
    if ($Kind -eq 'apps') {
        Assert-True ([bool] $Entry.main) ("$label has a main file")
        # A few app manifests point at TypeScript source rather than a build
        # artefact; the catalog mirrors the manifest either way.
        Assert-Match '^https://[^/]+/.+\.(js|mjs|cjs|jsx|tsx|ts)$' $Entry.rawUrl ("$label raw url is an https source url")
        Assert-Match '^https://github\.com/' $Entry.repoUrl ("$label repo url is https")
        Assert-True ($null -ne $Entry.stars) ("$label has a star count")
    }
    if ($Kind -eq 'themes') {
        Assert-True ([bool] $Entry.branch) ("$label has a branch")
    }
}

function Invoke-CatalogSection {
    Write-Section 'catalog - entries are complete and unique'

    $catalog = Read-TextFile (Join-Path $script:Root 'catalog\catalog.json') | ConvertFrom-Json

    foreach ($kind in @('extensions', 'themes', 'apps')) {
        $entries = @($catalog.$kind)
        Assert-True ($entries.Count -gt 0) ("catalog $kind is not empty")

        $seen = @{}
        foreach ($entry in $entries) { Test-CatalogEntry -Entry $entry -Kind $kind -Seen $seen }
        Assert-Equal $entries.Count $seen.Count ("$kind ids are unique")

        $archived = @($entries | Where-Object { $_.archived })
        Assert-Equal 0 $archived.Count ("$kind excludes archived repositories")
    }

    $xs = @($catalog.extensions)
    $badUrls = @($xs | Where-Object { $_.rawUrl -notmatch '^https://[^/]+/.+\.(js|mjs|cjs)$' })
    Assert-True ($badUrls.Count -eq 0) ("every extension raw url points at a js file ({0} unexpected)" -f $badUrls.Count)

    $duplicateUrls = @($xs | Group-Object rawUrl | Where-Object { $_.Count -gt 1 })
    Assert-True ($duplicateUrls.Count -eq 0) ("no two extensions share a raw url ({0} duplicates)" -f $duplicateUrls.Count)
}

# ---------------------------------------------------------------- presets

function Invoke-PresetSection {
    Write-Section 'presets - resolvable against the catalog'

    $catalog = Read-TextFile (Join-Path $script:Root 'catalog\catalog.json') | ConvertFrom-Json
    $ids = @{}
    foreach ($entry in $catalog.extensions) { $ids[$entry.id] = $entry }

    $files = @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'presets') -Filter '*.json' -File)
    Assert-True ($files.Count -ge 3) 'at least three presets exist'

    foreach ($file in $files) {
        $preset = Read-TextFile $file.FullName | ConvertFrom-Json
        Assert-Equal $file.BaseName $preset.name ("{0} name matches its file" -f $file.Name)
        Assert-Equal 1 $preset.schemaVersion ("{0} schemaVersion is 1" -f $file.Name)
        Assert-True ([bool] $preset.description) ("{0} has a description" -f $file.Name)
        Assert-True ($preset.PSObject.Properties.Name -contains 'all') ("{0} declares 'all'" -f $file.Name)

        foreach ($id in @($preset.extensions)) {
            Assert-True ($ids.ContainsKey($id)) ("{0} references {1}" -f $file.Name, $id)
            if ($id -match '^[a-z0-9][a-z0-9-]*-[a-z0-9][a-z0-9-]*--[a-z0-9][a-z0-9-]*$') {
                Add-Pass ("{0} id {1} fits the managed file pattern" -f $file.Name, $id)
            } else {
                Add-Fail ("{0} id {1} does not fit 'vendor-repo--name'" -f $file.Name, $id)
            }
        }
        foreach ($id in @($preset.exclude)) {
            Assert-True ($ids.ContainsKey($id)) ("{0} excludes a known id ({1})" -f $file.Name, $id)
        }
    }

    $lean = Read-TextFile (Join-Path $script:Root 'presets\lean.json') | ConvertFrom-Json
    Assert-True ($lean.extensions.Count -ge 1 -and $lean.extensions.Count -le 30) ("lean preset stays small ({0} extensions)" -f $lean.extensions.Count)
    Assert-Equal $false $lean.all 'lean preset is curated, not the whole catalog'

    $full = Read-TextFile (Join-Path $script:Root 'presets\full.json') | ConvertFrom-Json
    Assert-Equal $true $full.all 'full preset starts from the whole catalog'

    $minimal = Read-TextFile (Join-Path $script:Root 'presets\minimal.json') | ConvertFrom-Json
    Assert-Equal 0 $minimal.extensions.Count 'minimal preset installs no third-party extension'
}

# ---------------------------------------------------------------- policy

function Invoke-PolicySection {
    Write-Section 'policy - blocks what it says it blocks'

    $policy = Read-TextFile (Join-Path $script:Root 'data\policy.json') | ConvertFrom-Json
    Assert-Equal 1 $policy.schemaVersion 'policy schemaVersion is 1'
    Assert-True (@($policy.blockedPatterns).Count -ge 1) 'at least one blocked pattern exists'
    Assert-True (@($policy.conflictGroups).Count -ge 1) 'at least one conflict group exists'

    $catalog = Read-TextFile (Join-Path $script:Root 'catalog\catalog.json') | ConvertFrom-Json
    $lean = Read-TextFile (Join-Path $script:Root 'presets\lean.json') | ConvertFrom-Json
    $byId = @{}
    foreach ($entry in $catalog.extensions) { $byId[$entry.id] = $entry }

    foreach ($id in @($lean.extensions)) {
        $entry = $byId[$id]
        if ($null -eq $entry) {
            Add-Fail ("lean preset references an unknown id: {0}" -f $id)
            continue
        }
        foreach ($rule in @($policy.blockedPatterns)) {
            $hit = ($entry.id -match $rule.pattern) -or ($entry.name -match $rule.pattern) -or ($entry.repo -match $rule.pattern)
            Assert-True (-not $hit) ("lean extension {0} is not blocked by '{1}'" -f $id, $rule.pattern)
        }
    }

    # Resolve the full preset through the module when it can be imported, and check
    # that no conflict group kept two members.
    $module = Import-LeanModule
    if (-not $module) { Add-Skip 'conflict-group resolution (module unavailable)'; return }

    $preset = & $module { param($p) Get-LeanPreset -Name $p } 'full'
    $targets = & $module { param($p, $c, $pol) Resolve-LeanPresetTargets -Preset $p -Catalog $c -Policy $pol } $preset (Get-LeanCatalogDataForTest $module) $policy
    Assert-True (@($targets).Count -gt 0) ("full preset resolves to {0} extensions" -f @($targets).Count)

    foreach ($group in @($policy.conflictGroups)) {
        $members = @($targets | Where-Object {
            $_.name -match $group.pattern -or $_.repo -match $group.pattern -or (($_.tags -join ' ') -match $group.pattern)
        })
        Assert-True ($members.Count -le 1) ("conflict group '{0}' keeps {1} member(s)" -f $group.id, $members.Count)
    }

    $blocked = @($targets | Where-Object {
        $entry = $_
        $match = $false
        foreach ($rule in @($policy.blockedPatterns)) {
            if (($entry.id -match $rule.pattern) -or ($entry.name -match $rule.pattern) -or ($entry.repo -match $rule.pattern)) { $match = $true }
        }
        $match
    })
    Assert-Equal 0 $blocked.Count 'full preset contains no blocked extension'
}

function Get-LeanCatalogDataForTest {
    param($Module)
    return (& $Module { Get-LeanCatalogData })
}

# ---------------------------------------------------------------- module

function Import-LeanModule {
    if ($script:LeanModule) { return $script:LeanModule }
    try {
        $script:LeanModule = Import-Module (Join-Path $script:Root 'src\Lean.psd1') -Force -PassThru -ErrorAction Stop
    } catch {
        Add-Fail ("module import failed: {0}" -f $_.Exception.Message)
        $script:LeanModule = $null
    }
    return $script:LeanModule
}

function Invoke-ModuleSection {
    Write-Section 'module - public surface and context'

    $module = Import-LeanModule
    if (-not $module) { return }

    Assert-Equal 'Lean' $module.Name 'module name is Lean'
    Assert-Equal '0.1.0' ("{0}" -f $module.Version) 'module version is 0.1.0'

    $expected = @(
        'Invoke-LeanInstall', 'Invoke-LeanApply', 'Set-LeanDebloat',
        'Install-LeanExtensionSet', 'Install-LeanTheme', 'Get-LeanCatalog',
        'Get-LeanStatus', 'Test-LeanEnvironment', 'Measure-LeanPerformance', 'Restore-Lean'
    )
    $exported = @($module.ExportedFunctions.Keys)
    Assert-Equal $expected.Count $exported.Count 'ten functions are exported'
    foreach ($name in $expected) {
        Assert-True ($exported -contains $name) ("{0} is exported" -f $name)
    }

    $context = & $module { Get-LeanContext }
    Assert-Equal $script:Root $context.Root 'context root is the repository root'
    Assert-Match '\\spicetify\\Extensions$' $context.ExtensionRoot 'extensions resolve under LOCALAPPDATA\spicetify'
    Assert-Match '\\spicetify\\Themes$' $context.ThemeRoot 'themes resolve under APPDATA\spicetify'
    Assert-Match 'lean-state\.json$' $context.StatePath 'state file is lean-state.json'
    Assert-True ($context.PSObject.Properties.Name -contains 'SpotifyVersion') 'context exposes the Spotify version'

    $top = @(& $module { Get-LeanCatalog -Kind extensions -Top 3 })
    Assert-Equal 3 $top.Count 'catalog query honours -Top'
    Assert-True ($top[0].PSObject.Properties.Name -contains 'installed') 'catalog query reports installation state'

    $filtered = @(& $module { Get-LeanCatalog -Kind extensions -Search 'shuffle' -Top 5 })
    Assert-True ($filtered.Count -ge 1 -and $filtered.Count -le 5) 'catalog search returns bounded results'

    $all = @(& $module { Get-LeanCatalog -Kind all })
    Assert-True ($all.Count -eq 1) 'catalog -Kind all returns one object'
    Assert-True (@($all[0].extensions).Count -gt 0) 'catalog -Kind all includes extensions'
    Assert-True (@($all[0].snippets).Count -gt 0) 'catalog -Kind all includes snippets'

    # Dry run must not touch anything. It still runs the preflight, so it only makes
    # sense where a client exists.
    if ($context.SpotifyVersion -and $context.SpicetifyExe) {
        $dry = & $module { Invoke-LeanInstall -Profile lean -DryRun } 6>$null
        Assert-Equal $true $dry.DryRun 'install -DryRun reports a dry run'
    } else {
        Add-Skip 'install -DryRun (no client on this machine)'
    }

    # Command references must resolve to functions defined in src/ or the entry script.
    $defined = New-Object 'System.Collections.Generic.HashSet[string]'
    $definitionFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'src') -Recurse -Filter '*.ps1' -File) +
        @(Get-ChildItem -LiteralPath $script:Root -Filter 'lean.ps1' -File)
    foreach ($file in $definitionFiles) {
        foreach ($match in [Regex]::Matches((Read-TextFile $file.FullName), '(?m)^\s*function\s+([A-Za-z][A-Za-z0-9]*-[A-Za-z][A-Za-z0-9]*)')) {
            [void] $defined.Add($match.Groups[1].Value)
        }
    }
    $localPattern = '^(Get|Set|Invoke|Install|Measure|Restore|Test|Format|Write|Assert|Save|Backup|New|Resolve|Read|Stop|Start|Wait)-(Lean|Spicetify|Spotify)'
    $missing = New-Object System.Collections.ArrayList
    $scanned = @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'src') -Recurse -Filter '*.ps1' -File) +
        @(Get-ChildItem -LiteralPath $script:Root -Filter 'lean.ps1' -File)
    foreach ($file in $scanned) {
        foreach ($match in [Regex]::Matches((Read-TextFile $file.FullName), '(?m)\b((?:Get|Set|Invoke|Install|Measure|Restore|Test|Format|Write|Assert|Save|Backup|New|Resolve|Read|Stop|Start|Wait)-(?:Lean|Spicetify|Spotify)[A-Za-z0-9]*)\b')) {
            $name = $match.Groups[1].Value
            if ($name -match $localPattern -and -not $defined.Contains($name)) {
                if (-not $missing.Contains($name)) { [void] $missing.Add($name) }
            }
        }
    }
    Assert-True ($missing.Count -eq 0) ("every internal command reference is defined ({0} undefined: {1})" -f $missing.Count, ($missing -join ', '))

    # Live checks only where a client actually exists.
    if ($context.SpotifyVersion -and $context.SpicetifyExe) {
        $status = & $module { Get-LeanStatus }
        Assert-True ($status.SpotifyVersion -eq $context.SpotifyVersion) 'status reports the installed Spotify version'
        $list = @(& $module { Get-SpicetifyConfigList -Key 'extensions' })
        Assert-True ($list -is [array] -or $null -eq $list) 'extension list is read as an array'
        $single = & $module { Get-SpicetifyConfigValue -Key 'current_theme' }
        Assert-True ($single -is [string]) 'scalar settings are read as a single string'

        $checks = @(& $module { Test-LeanEnvironment })
        $fails = @($checks | Where-Object { $_.Status -eq 'FAIL' })
        Assert-Equal 0 $fails.Count ("doctor reports no FAIL ({0})" -f (($fails | ForEach-Object { $_.Name }) -join ', '))
    } else {
        Add-Skip 'live Spotify/Spicetify checks (no client on this machine)'
    }
}

# ---------------------------------------------------------------- theme

function Invoke-ThemeSection {
    Write-Section 'theme - files, guard rails and syntax'

    $themeDir = Join-Path $script:Root 'theme'
    foreach ($name in @('user.css', 'color.ini', 'lean-ui.js')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $themeDir $name)) ("theme/{0} exists" -f $name)
    }

    $css = Read-TextFile (Join-Path $themeDir 'user.css')
    $open = ([Regex]::Matches($css, '\{')).Count
    $close = ([Regex]::Matches($css, '\}')).Count
    Assert-Equal $open $close 'user.css braces are balanced'
    Assert-True ($css -notmatch '@import') 'user.css has no @import'
    Assert-True ($css -notmatch 'url\(\s*[''"]?https?:') 'user.css loads no remote resources'
    Assert-Match 'data-lean' $css 'debloat rules are gated on data-lean'
    Assert-Match ':root:not\(\[data-lean="0"\]\)' $css 'debloat rules can be switched off at runtime'
    foreach ($dead in @('Root__nav-bar', 'Root__main-view', 'main-trackList-row', 'main-card-card', 'main-shelf-shelf')) {
        Assert-True ($css -notmatch [Regex]::Escape($dead)) ("user.css no longer references the dead 2022 class {0}" -f $dead)
    }
    Assert-Match '--encore-corner-radius-base' $css 'Encore radius tokens are mapped'
    Assert-Match '--background-base' $css 'Encore background tokens are mapped'
    Assert-Match 'clamp\(' $css 'entity titles are capped'

    $color = Read-TextFile (Join-Path $themeDir 'color.ini')
    foreach ($section in @('[Lean]', '[Lean Light]')) {
        Assert-True ($color.Contains($section)) ("color.ini defines {0}" -f $section)
    }
    foreach ($key in @('text', 'subtext', 'main', 'player', 'card', 'button', 'notification-error')) {
        Assert-True ([Regex]::IsMatch($color, "(?m)^$key\s*=\s*[0-9A-Fa-f]{6}\s*$")) ("color.ini sets a 6-digit hex for {0}" -f $key)
    }

    $js = Read-TextFile (Join-Path $themeDir 'lean-ui.js')
    Assert-Match 'window\.Lean' $js 'lean-ui.js exposes window.Lean'
    Assert-Match 'data-lean' $js 'lean-ui.js drives the data-lean attribute'
    Assert-True ($js -notmatch 'fetch\(|XMLHttpRequest|WebSocket') 'lean-ui.js makes no network calls'
    Assert-True ($js -notmatch 'setInterval\([^)]*,\s*(?:[0-4]?\d)\s*\)\s*;\s*$') 'lean-ui.js has no tight polling loop'

    if (Test-Node) {
        $result = & node --check (Join-Path $themeDir 'lean-ui.js') 2>&1
        Assert-Equal 0 $LASTEXITCODE 'lean-ui.js passes node --check'
        if ($LASTEXITCODE -ne 0) { Write-Host $result -ForegroundColor DarkRed }

        foreach ($tool in @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'tools') -Filter '*.mjs' -File)) {
            $null = & node --check $tool.FullName 2>&1
            Assert-Equal 0 $LASTEXITCODE ("tools/{0} passes node --check" -f $tool.Name)
        }
    } else {
        Add-Skip 'node --check (Node.js not installed)'
    }
}

# ---------------------------------------------------------------- style

function Invoke-StyleSection {
    Write-Section 'style - PowerShell 5.1 compatibility and parser checks'

    $scripts = @(Get-RepoFiles -Extension @('.ps1', '.psm1', '.psd1'))
    Assert-True ($scripts.Count -ge 15) ("found {0} PowerShell files" -f $scripts.Count)

    foreach ($file in $scripts) {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        $relative = $file.FullName.Substring($script:Root.Length).TrimStart('\')
        if (@($errors).Count -eq 0) {
            Add-Pass ("$relative parses")
        } else {
            Add-Fail ("$relative has {0} parse error(s): {1}" -f @($errors).Count, (($errors | ForEach-Object { $_.Message }) -join '; '))
        }
    }

    # Tokens are assembled at runtime so this file does not trip its own scan.
    $forbidden = @(
        @{ Token = (-join ([char]63, [char]63)); Label = 'null-coalescing operator' },
        @{ Token = ('-Para' + 'llel'); Label = 'parallel ForEach-Object' }
    )

    $offenders = New-Object System.Collections.ArrayList
    foreach ($file in $scripts) {
        $text = Read-TextFile $file.FullName
        $relative = $file.FullName.Substring($script:Root.Length).TrimStart('\')
        foreach ($rule in $forbidden) {
            if ($text -match [Regex]::Escape($rule.Token)) {
                [void] $offenders.Add(("{0} uses {1}" -f $relative, $rule.Label))
            }
        }
        if ($text -match "`t") { [void] $offenders.Add(("{0} contains a tab" -f $relative)) }
        if ($text -match '(?m)^\s*\?[^:]*:') { [void] $offenders.Add(("{0} uses a C-style ternary" -f $relative)) }
    }
    Assert-Equal 0 $offenders.Count ("no PowerShell 5.1 incompatibilities ({0})" -f ($offenders -join '; '))

    $big = @(Get-RepoFiles -Extension @('.json', '.ps1', '.psm1', '.psd1', '.js', '.mjs', '.css', '.ini', '.md') |
        Where-Object { $_.Length -gt 2MB })
    Assert-Equal 0 $big.Count ("no text file exceeds 2 MB ({0})" -f (($big | ForEach-Object { $_.Name }) -join ', '))

    $lean = Read-TextFile (Join-Path $script:Root 'lean.ps1')
    Assert-Match 'Import-Module' $lean 'lean.ps1 imports the module'
    Assert-True ($lean -notmatch 'Start-Process -FilePath.*Spotify') 'lean.ps1 does not launch Spotify directly'
}

# ---------------------------------------------------------------- privacy

function Invoke-PrivacySection {
    Write-Section 'privacy - no personal paths, tokens or credentials'

    $patterns = @(
        # The path separator is written as a character class so this file never
        # matches its own privacy pattern.
        @{ Name = 'absolute Windows user path'; Pattern = '(?i)C:[\\/]Users[\\/][^\\/\r\n]+' },
        @{ Name = 'GitHub personal access token'; Pattern = 'gh[pousr]_[A-Za-z0-9]{20,}' },
        @{ Name = 'GitHub fine-grained token'; Pattern = 'github_pat_[A-Za-z0-9_]{20,}' },
        @{ Name = 'AWS access key id'; Pattern = 'AKIA[0-9A-Z]{16}' },
        @{ Name = 'Slack token'; Pattern = 'xox[baprs]-[0-9A-Za-z-]{10,}' },
        @{ Name = 'private key block'; Pattern = '-----BEGIN [A-Z ]*PRIVATE KEY-----' }
    )

    $userName = $env:USERNAME
    if ($userName -and $userName.Length -ge 3) {
        $patterns += @{ Name = 'local user name'; Pattern = ('(?i)\b{0}\b' -f [Regex]::Escape($userName)) }
    }

    $files = @(Get-RepoFiles -Extension @('.ps1', '.psm1', '.psd1', '.json', '.js', '.mjs', '.css', '.ini', '.md', '.yml', '.yaml', '.txt'))
    Assert-True ($files.Count -ge 20) ("scanned {0} text files" -f $files.Count)

    $hits = New-Object System.Collections.ArrayList
    foreach ($file in $files) {
        $text = Read-TextFile $file.FullName
        $relative = $file.FullName.Substring($script:Root.Length).TrimStart('\')
        foreach ($rule in $patterns) {
            if ($text -match $rule.Pattern) {
                [void] $hits.Add(("{0} contains a {1}" -f $relative, $rule.Name))
            }
        }
    }
    Assert-Equal 0 $hits.Count ("no secrets or personal identifiers ({0})" -f ($hits -join '; '))

    $stateInRepo = Test-Path -LiteralPath (Join-Path $script:Root 'lean-state.json')
    Assert-True (-not $stateInRepo) 'no lean-state.json is committed'
    $screens = @(Get-RepoFiles -Extension @('.png', '.jpg'))
    Assert-Equal 0 $screens.Count ("no screenshots are committed ({0})" -f (($screens | ForEach-Object { $_.Name }) -join ', '))
}

# ---------------------------------------------------------------- run

$sections = [ordered]@{
    json    = 'Invoke-JsonSection'
    catalog = 'Invoke-CatalogSection'
    presets = 'Invoke-PresetSection'
    policy  = 'Invoke-PolicySection'
    module  = 'Invoke-ModuleSection'
    theme   = 'Invoke-ThemeSection'
    style   = 'Invoke-StyleSection'
    privacy = 'Invoke-PrivacySection'
}

Write-Host ''
Write-Host '  spotify-debloat tests' -ForegroundColor White
Write-Host ("  root: {0}" -f $script:Root) -ForegroundColor DarkGray
Write-Host ("  host: PowerShell {0} on {1}" -f $PSVersionTable.PSVersion, $env:OS) -ForegroundColor DarkGray

foreach ($name in $sections.Keys) {
    if ($Section -ne 'all' -and $Section -ne $name) { continue }
    try {
        & $sections[$name]
    } catch {
        Add-Fail ("section threw: {0}" -f $_.Exception.Message)
    }
}

Write-Host ''
Write-Host '  summary' -ForegroundColor White
Write-Host ("    passed  {0}" -f $script:Passed) -ForegroundColor Green
Write-Host ("    failed  {0}" -f $script:Failed) -ForegroundColor $(if ($script:Failed -gt 0) { 'Red' } else { 'DarkGray' })
Write-Host ("    skipped {0}" -f $script:Skipped) -ForegroundColor DarkYellow

if ($script:Failed -gt 0) {
    Write-Host ''
    Write-Host '  failures' -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host ("    {0}" -f $failure) -ForegroundColor Red }
    Write-Host ''
    exit 1
}

Write-Host ''
Write-Host '  all good' -ForegroundColor Green
Write-Host ''
exit 0
