#Requires -Version 5.1

function Get-LeanCatalog {
    <#
    .SYNOPSIS
        Queries the committed Marketplace catalog.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('extensions', 'themes', 'apps', 'snippets', 'all')]
        [string] $Kind = 'extensions',
        [string] $Search,
        [string] $Tag,
        [int] $Top = 0,
        [switch] $Json
    )

    $catalog = Get-LeanCatalogData
    $context = Get-LeanContext

    if ($Kind -eq 'all') {
        # A PSCustomObject rather than a dictionary: it is a single stable object for
        # callers that want all four collections at once, and it serialises cleanly.
        $result = [pscustomobject]@{
            extensions = @($catalog.extensions)
            themes     = @($catalog.themes)
            apps       = @($catalog.apps)
            snippets   = @(Read-LeanJson -Path $context.SnippetsPath)
        }
        if ($Json) { return ($result | ConvertTo-Json -Depth 8) }
        return $result
    }

    $items = if ($Kind -eq 'snippets') {
        @(Read-LeanJson -Path $context.SnippetsPath)
    } else {
        @($catalog.$Kind)
    }

    if ($Search) {
        $items = @($items | Where-Object {
            $_.name -match $Search -or
            $_.title -match $Search -or
            $_.description -match $Search -or
            $_.repo -match $Search -or
            (($_.tags -join ' ') -match $Search)
        })
    }
    if ($Tag) {
        $items = @($items | Where-Object { $_.tags -and ($_.tags -contains $Tag) })
    }

    if ($Kind -eq 'extensions') {
        foreach ($item in $items) {
            $fileName = Get-LeanExtensionFileName -Entry $item
            $installed = Test-Path -LiteralPath (Join-Path $context.ExtensionRoot $fileName)
            $item | Add-Member -NotePropertyName installed -NotePropertyValue $installed -Force
        }
    }

    if ($Top -gt 0) { $items = @($items | Select-Object -First $Top) }
    if ($Json) { return ($items | ConvertTo-Json -Depth 8) }
    return $items
}
