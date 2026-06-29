function Get-AvmUpdateType {
    <#
    .SYNOPSIS
        Classifies the version bump between two semver strings as major, minor, patch, or none.
    .PARAMETER Current
        Current version string (e.g. '0.3.1').
    .PARAMETER Target
        Target version string (e.g. '0.4.0').
    .OUTPUTS
        String: 'major', 'minor', 'patch', or 'none'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Current,
        [Parameter(Mandatory)][string]$Target
    )

    $cur = ConvertTo-SemVer -Version $Current
    $tgt = ConvertTo-SemVer -Version $Target

    if ($null -eq $cur -or $null -eq $tgt) { return 'unknown' }

    if ($tgt.Major -gt $cur.Major) { return 'major' }
    if ($tgt.Major -eq $cur.Major -and $tgt.Minor -gt $cur.Minor) { return 'minor' }
    if ($tgt.Major -eq $cur.Major -and $tgt.Minor -eq $cur.Minor -and $tgt.Build -gt $cur.Build) { return 'patch' }
    if ($tgt -le $cur) { return 'none' }
    return 'unknown'
}
