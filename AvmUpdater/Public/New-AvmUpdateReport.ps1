function New-AvmUpdateReport {
    <#
    .SYNOPSIS
        Generates a Markdown overview and a JSON manifest from an AvmUpdater update plan.

    .DESCRIPTION
        Writes two files to the output directory:
        - avm-update-report.md  — human-readable overview with summary table, per-update detail
          for MEDIUM/HIGH, interface diff, changelog evidence, and separate sections for LOW,
          needs-review, and could-not-check modules.
        - avm-update-plan.json — machine-readable full plan (consumed by the updater).
        Pure function: no network calls.

    .PARAMETER Plan
        The enriched plan object returned by Get-AvmUpdatePlan.

    .PARAMETER OutputDirectory
        Directory where report files are written. Defaults to './avm-report'.

    .OUTPUTS
        PSCustomObject with: reportPath, jsonPath.

    .EXAMPLE
        $plan = Get-AvmUpdatePlan -Path ./infra
        New-AvmUpdateReport -Plan $plan -OutputDirectory ./avm-report
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Plan,

        [Parameter()]
        [string]$OutputDirectory = './avm-report'
    )

    # Ensure output directory exists
    if (-not (Test-Path $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $reportPath = Join-Path $OutputDirectory 'avm-update-report.md'
    $jsonPath   = Join-Path $OutputDirectory 'avm-update-plan.json'

    $s  = $Plan.summary
    $all = @($Plan.candidates) + @($Plan.lookupFailed)

    $high    = @($all | Where-Object riskTier -eq 'HIGH')
    $medium  = @($all | Where-Object riskTier -eq 'MEDIUM')
    $low     = @($all | Where-Object riskTier -eq 'LOW')
    $unknown = @($all | Where-Object riskTier -eq 'UNKNOWN')
    $failed  = @($Plan.lookupFailed)

    $md = [System.Text.StringBuilder]::new()

    # --- Header ---
    $null = $md.AppendLine("# AVM Update Report")
    $null = $md.AppendLine()
    $null = $md.AppendLine("**Scan date:** $($s.scannedAt)  ")
    $null = $md.AppendLine("**Paths scanned:** $($s.pathsScanned -join ', ')  ")
    $null = $md.AppendLine()
    $null = $md.AppendLine("## Summary")
    $null = $md.AppendLine()
    $null = $md.AppendLine("| Metric | Count |")
    $null = $md.AppendLine("|--------|-------|")
    $null = $md.AppendLine("| Modules scanned | $($s.totalRefs) |")
    $null = $md.AppendLine("| Updates available | $($s.totalUpdates) |")
    $null = $md.AppendLine("| Major bumps | $($s.byUpdateType.major) |")
    $null = $md.AppendLine("| Minor bumps | $($s.byUpdateType.minor) |")
    $null = $md.AppendLine("| Patch bumps | $($s.byUpdateType.patch) |")
    $null = $md.AppendLine("| HIGH risk | $($s.byRiskTier.HIGH) |")
    $null = $md.AppendLine("| MEDIUM risk | $($s.byRiskTier.MEDIUM) |")
    $null = $md.AppendLine("| LOW risk | $($s.byRiskTier.LOW) |")
    $null = $md.AppendLine("| UNKNOWN risk | $($s.byRiskTier.UNKNOWN) |")
    $null = $md.AppendLine("| Lookup failed | $($s.lookupFailed) |")
    $null = $md.AppendLine()

    # --- Summary table ---
    if ($Plan.candidates.Count -gt 0) {
        $null = $md.AppendLine("## All Update Candidates")
        $null = $md.AppendLine()
        $null = $md.AppendLine("| Module | Ecosystem | Current | Latest | Jump | Risk | File:Line |")
        $null = $md.AppendLine("|--------|-----------|---------|--------|------|------|-----------|")

        # Sort: HIGH first, then MEDIUM, LOW, UNKNOWN
        $sorted = $Plan.candidates | Sort-Object {
            switch ($_.riskTier) { 'HIGH' { 0 } 'MEDIUM' { 1 } 'LOW' { 2 } default { 3 } }
        }, module

        foreach ($c in $sorted) {
            $fileRef = "$([System.IO.Path]::GetFileName($c.file)):$($c.lineNumber)"
            $null = $md.AppendLine("| $($c.module) | $($c.ecosystem) | $($c.currentVersion) | $($c.latestStable) | $($c.updateType) | $($c.riskTier) | $fileRef |")
        }
        $null = $md.AppendLine()
    }

    # --- Needs Review section (HIGH + MEDIUM) ---
    $needsReview = @($high) + @($medium)
    if ($needsReview.Count -gt 0) {
        $null = $md.AppendLine("## Needs Review (HIGH / MEDIUM)")
        $null = $md.AppendLine()
        foreach ($c in $needsReview) {
            $null = $md.AppendLine("### $($c.module) ($($c.ecosystem)) — $($c.riskTier)")
            $null = $md.AppendLine()
            $null = $md.AppendLine("- **File:** ``$($c.file):$($c.lineNumber)``")
            $null = $md.AppendLine("- **Change:** $($c.currentVersion) → $($c.latestStable) ($($c.updateType))")
            $null = $md.AppendLine()

            if ($c.riskReasons.Count -gt 0) {
                $null = $md.AppendLine("**Risk Reasons:**")
                $null = $md.AppendLine()
                foreach ($r in $c.riskReasons) { $null = $md.AppendLine("- $r") }
                $null = $md.AppendLine()
            }

            $diff = $c.interfaceDiff
            if ($diff -and $diff.available) {
                $null = $md.AppendLine("**Interface Diff:**")
                $null = $md.AppendLine()
                if ($diff.addedRequired.Count)  { $null = $md.AppendLine("- Added required inputs: $($diff.addedRequired -join ', ')") }
                if ($diff.removedInputs.Count)  { $null = $md.AppendLine("- Removed inputs: $($diff.removedInputs -join ', ')") }
                if ($diff.typeChanged.Count)    { $null = $md.AppendLine("- Type changes: $($diff.typeChanged -join ', ')") }
                if ($diff.addedOptional.Count)  { $null = $md.AppendLine("- Added optional inputs: $($diff.addedOptional -join ', ')") }
                if ($diff.removedOutputs.Count) { $null = $md.AppendLine("- Removed outputs: $($diff.removedOutputs -join ', ')") }
                if ($diff.addedOutputs.Count)   { $null = $md.AppendLine("- Added outputs: $($diff.addedOutputs -join ', ')") }
                $null = $md.AppendLine()
            }

            if ($c.changelogLines.Count -gt 0) {
                $null = $md.AppendLine("**Changelog Evidence:**")
                $null = $md.AppendLine()
                foreach ($l in $c.changelogLines) { $null = $md.AppendLine("- $l") }
                $null = $md.AppendLine()
            }
        }
    }

    # --- Likely Safe section (LOW) ---
    if ($low.Count -gt 0) {
        $null = $md.AppendLine("## Likely Safe (LOW)")
        $null = $md.AppendLine()
        $null = $md.AppendLine("| Module | Ecosystem | Current | Latest | File:Line |")
        $null = $md.AppendLine("|--------|-----------|---------|--------|-----------|")
        foreach ($c in $low) {
            $fileRef = "$([System.IO.Path]::GetFileName($c.file)):$($c.lineNumber)"
            $null = $md.AppendLine("| $($c.module) | $($c.ecosystem) | $($c.currentVersion) | $($c.latestStable) | $fileRef |")
        }
        $null = $md.AppendLine()
    }

    # --- Could Not Check (UNKNOWN + lookup-failed) ---
    $cantCheck = @($unknown) + @($failed)
    if ($cantCheck.Count -gt 0) {
        $null = $md.AppendLine("## Could Not Check")
        $null = $md.AppendLine()
        foreach ($c in $cantCheck) {
            $modName = try {
                if ($c.PSObject.Properties['module'] -and $null -ne $c.module) { $c.module }
                elseif ($c.PSObject.Properties['reference'] -and $null -ne $c.reference) { $c.reference.module }
                else { 'unknown' }
            } catch { 'unknown' }
            $null = $md.AppendLine("- **$modName**: $($c.riskReasons -join '; ')")
        }
        $null = $md.AppendLine()
    }

    # Write files
    Set-Content -Path $reportPath -Value $md.ToString() -Encoding UTF8
    $Plan | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

    return [PSCustomObject]@{
        reportPath = $reportPath
        jsonPath   = $jsonPath
    }
}
