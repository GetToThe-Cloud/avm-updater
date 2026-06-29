function Get-AvmChangelog {
    <#
    .SYNOPSIS
        Fetches changelog/release-note lines mentioning breaking changes between two versions.
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$Reference,
        [string]$TargetVersion,
        [int]$MaxLines = 10
    )

    $result = [PSCustomObject]@{
        available = $false
        lines     = @()
        source    = $null
    }

    try {
        if ($Reference.ecosystem -eq 'bicep') {
            $tagPrefix   = "avm/$($Reference.category)/$($Reference.group)/$($Reference.module)"
            $changelogUrl = "https://raw.githubusercontent.com/Azure/bicep-registry-modules/main/avm/$($Reference.category)/$($Reference.group)/$($Reference.module)/CHANGELOG.md"
            $content = Invoke-RestMethod -Uri $changelogUrl -TimeoutSec 15 -ErrorAction Stop
            $result.source    = $changelogUrl
            $result.available = $true
            $result.lines     = ExtractBreakingLines -Content $content -MaxLines $MaxLines
        } elseif ($Reference.ecosystem -eq 'terraform') {
            $repoName = $Reference.module -replace '^avm-', 'terraform-azurerm-avm-'
            $releasesUrl = "https://api.github.com/repos/Azure/$repoName/releases"
            $headers = @{ 'User-Agent' = 'AvmUpdater/0.1' }
            if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
            $releases = Invoke-RestMethod -Uri $releasesUrl -Headers $headers -TimeoutSec 15 -ErrorAction Stop

            $curVer = [System.Version]($Reference.currentVersion -replace '^v|~>\s*', '')
            $tgtVer = [System.Version]($TargetVersion -replace '^v', '')

            $relevantBodies = $releases |
                Where-Object {
                    $tag = $_.tag_name -replace '^v', ''
                    try {
                        $v = [System.Version]$tag
                        $v -gt $curVer -and $v -le $tgtVer
                    } catch { $false }
                } |
                ForEach-Object { $_.body }

            $combined         = $relevantBodies -join "`n"
            $result.source    = $releasesUrl
            $result.available = $true
            $result.lines     = ExtractBreakingLines -Content $combined -MaxLines $MaxLines
        }
    } catch {
        Write-Verbose "Changelog unavailable for $($Reference.registryPath): $_"
    }

    return $result
}

function ExtractBreakingLines {
    param([string]$Content, [int]$MaxLines = 10)

    $lines   = $Content -split "`n"
    $results = [System.Collections.Generic.List[string]]::new()
    $inBreakingSection = $false

    foreach ($line in $lines) {
        # Detect a Breaking Changes section heading
        if ($line -match '^#{1,4}\s*(BREAKING CHANGE|Breaking Changes)') {
            $inBreakingSection = $true
            continue
        }
        # Stop at the next same-or-higher-level heading
        if ($inBreakingSection -and $line -match '^#{1,4}\s+' -and $line -notmatch '(?i)breaking') {
            $inBreakingSection = $false
        }
        # Collect non-empty content lines within the section
        if ($inBreakingSection -and $line.Trim() -ne '') {
            $results.Add($line.Trim())
            if ($results.Count -ge $MaxLines) { break }
        }
        # Also capture inline BREAKING CHANGE markers outside sections
        if (-not $inBreakingSection -and $line -match '(?i)BREAKING CHANGE') {
            $results.Add($line.Trim())
            if ($results.Count -ge $MaxLines) { break }
        }
    }

    # If nothing found in sections, fall back to lines mentioning removal/rename
    if ($results.Count -eq 0) {
        $results.AddRange(
            @($lines | Where-Object { $_ -match '(?i)(remov|renam|deprecat|incompatible)' } |
              Select-Object -First $MaxLines)
        )
    }

    return $results.ToArray()
}
