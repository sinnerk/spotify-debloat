#Requires -Version 5.1

function Write-LeanLog {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [AllowEmptyString()] [string] $Message = '',
        [ValidateSet('Step', 'Info', 'Ok', 'Warn', 'Error', 'Debug')] [string] $Level = 'Info'
    )

    if ($Level -eq 'Debug' -and -not $VerbosePreference.ToString().Equals('Continue')) { return }
    if ($script:LeanQuiet -and $Level -notin @('Warn', 'Error')) { return }

    $prefix = switch ($Level) {
        'Step'  { '::' }
        'Ok'    { ' +' }
        'Warn'  { ' !' }
        'Error' { ' x' }
        'Debug' { ' .' }
        default { '  ' }
    }
    $color = switch ($Level) {
        'Step'  { 'Cyan' }
        'Ok'    { 'Green' }
        'Warn'  { 'Yellow' }
        'Error' { 'Red' }
        'Debug' { 'DarkGray' }
        default { 'Gray' }
    }
    Write-Host ("{0} {1}" -f $prefix, $Message) -ForegroundColor $color
}

function Write-LeanBanner {
    param([string] $Title, [string] $Subtitle)
    Write-Host ''
    Write-Host '  spicetify-lean' -ForegroundColor DarkGray
    Write-Host ("  {0}" -f $Title) -ForegroundColor White
    if ($Subtitle) { Write-Host ("  {0}" -f $Subtitle) -ForegroundColor DarkGray }
    Write-Host ''
}

function Format-LeanBytes {
    param([double] $Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} B' -f $Bytes)
}
