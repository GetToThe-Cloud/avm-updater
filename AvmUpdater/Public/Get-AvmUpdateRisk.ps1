function Get-AvmUpdateRisk {
    <#
    .SYNOPSIS
        Assesses the breaking-change risk of upgrading a single AVM module from current to
        target version.

    .DESCRIPTION
        Gathers three independent signals to classify risk:
        1. Version semantics (major bump = HIGH; 0.x minor = potentially breaking; patch = LOW).
        2. Interface diff — compares inputs/outputs between current and target version using
           module metadata or source files. Breaking changes (required input added, input removed/
           renamed, type changed, output removed/renamed) raise risk to HIGH.
        3. Changelog evidence — extracts breaking-change mentions from CHANGELOG.md or GitHub
           Releases between the two versions.
        Returns a risk tier (HIGH | MEDIUM | LOW | UNKNOWN) plus concrete riskReasons[].

    .PARAMETER Reference
        The AVM module reference object from Get-AvmModuleReference.

    .PARAMETER TargetVersion
        The version to upgrade to.

    .OUTPUTS
        PSCustomObject with: riskTier, riskReasons[], interfaceDiff, changelogLines[].

    .EXAMPLE
        $ref = Get-AvmModuleReference -Path ./infra | Select-Object -First 1
        Get-AvmUpdateRisk -Reference $ref -TargetVersion '0.5.0'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Reference,

        [Parameter(Mandatory)]
        [string]$TargetVersion
    )

    $riskReasons     = [System.Collections.Generic.List[string]]::new()
    $updateType      = Get-AvmUpdateType -Current $Reference.currentVersion -Target $TargetVersion

    # --- Signal 1: Version semantics ---
    switch ($updateType) {
        'major' {
            $riskReasons.Add("Major version bump ($($Reference.currentVersion) → $TargetVersion) — may contain breaking changes by semver contract.")
        }
        'minor' {
            if ($Reference.currentVersion -match '^0\.') {
                $riskReasons.Add("0.x minor bump ($($Reference.currentVersion) → $TargetVersion) — AVM modules in 0.x treat minor as potentially breaking.")
            }
        }
        'patch' { <# patch is expected non-breaking by semver #> }
    }

    # --- Signal 2: Interface diff ---
    $diff = Get-AvmInterfaceDiff -Reference $Reference -TargetVersion $TargetVersion

    $interfaceBreaking = $false
    if ($diff.available) {
        foreach ($p in $diff.addedRequired)  { $riskReasons.Add("BREAKING: Required input added with no default: '$p'"); $interfaceBreaking = $true }
        foreach ($p in $diff.removedInputs)  { $riskReasons.Add("BREAKING: Input removed/renamed: '$p'"); $interfaceBreaking = $true }
        foreach ($p in $diff.typeChanged)    { $riskReasons.Add("BREAKING: Type changed: $p"); $interfaceBreaking = $true }
        foreach ($o in $diff.removedOutputs) { $riskReasons.Add("BREAKING: Output removed/renamed: '$o'"); $interfaceBreaking = $true }
        foreach ($p in $diff.addedOptional)  { $riskReasons.Add("Non-breaking: New optional input added: '$p'") }
        foreach ($o in $diff.addedOutputs)   { $riskReasons.Add("Non-breaking: New output added: '$o'") }
    }

    # --- Signal 3: Changelog ---
    $changelog = Get-AvmChangelog -Reference $Reference -TargetVersion $TargetVersion
    $changelogBreaking = $false
    if ($changelog.available -and $changelog.lines.Count -gt 0) {
        $changelogBreaking = $true
        foreach ($l in $changelog.lines) { $riskReasons.Add("Changelog: $l") }
    }

    # --- Determine risk tier (UNKNOWN check BEFORE patch-LOW) ---
    $riskTier = if ($updateType -eq 'major' -or $interfaceBreaking -or $changelogBreaking) {
        'HIGH'
    } elseif (-not $diff.available -and -not $changelog.available) {
        $riskReasons.Add("UNKNOWN: Interface diff and changelog unavailable — cannot confirm safety.")
        'UNKNOWN'
    } elseif ($updateType -eq 'minor' -and ($Reference.currentVersion -match '^0\.')) {
        'MEDIUM'
    } elseif ($updateType -eq 'patch' -and -not $interfaceBreaking) {
        'LOW'
    } else {
        # diff available, no breaking changes, minor on 1.x+ or other cases
        'MEDIUM'
    }

    return [PSCustomObject]@{
        riskTier       = $riskTier
        riskReasons    = $riskReasons.ToArray()
        interfaceDiff  = $diff
        changelogLines = if ($changelog.available) { $changelog.lines } else { @() }
    }
}
