function ConvertTo-SemVer {
    <#
    .SYNOPSIS
        Parses a version string into a sortable [semver] object, returning $null for invalid input.
    #>
    [CmdletBinding()]
    param([string]$Version)

    # Strip leading 'v' if present
    $clean = $Version -replace '^v', ''
    try {
        return [System.Version]::new($clean)
    } catch {
        return $null
    }
}

function Sort-SemVer {
    <#
    .SYNOPSIS
        Sorts an array of version strings in descending semver order, filtering out invalid entries.
    #>
    [CmdletBinding()]
    param([string[]]$Versions)

    return $Versions |
        Where-Object { $_ -match '^\d+\.\d+(\.\d+)?(\.\d+)?$' -and $_ -notmatch '(preview|alpha|beta|rc)' } |
        Sort-Object { [System.Version]($_ -replace '^v', '') } -Descending
}
