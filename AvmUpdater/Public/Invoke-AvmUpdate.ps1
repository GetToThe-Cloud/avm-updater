function Invoke-AvmUpdate {
    <#
    .SYNOPSIS
        End-to-end AVM update pipeline: scan → plan → report → approve → update.

    .DESCRIPTION
        Orchestrates the full AvmUpdater workflow:
        1. Get-AvmUpdatePlan (scan + version lookup + risk analysis).
        2. Filter by -IncludeRisk.
        3. New-AvmUpdateReport (always generated, even with zero candidates).
        4. If zero candidates, print "Everything is up to date" and exit 0.
        5. Approve-AvmUpdate (interactive, PR, etc.).
        6. Update-AvmModuleVersion (local mode) or surface PR validation results
           (github/azuredevops mode where updates ran inside approval).
        7. Print final summary (updated, skipped, rolled back, warnings, report path, PR URL).
        Idempotent — re-running when already current is a no-op.

    .PARAMETER Path
        Root directory to scan. Defaults to the current directory.

    .PARAMETER Exclude
        Array of glob patterns to exclude.

    .PARAMETER ApprovalMode
        Approval mechanism: 'local', 'github', or 'azuredevops'. Defaults to 'local'.

    .PARAMETER IncludeRisk
        Risk tiers to include in the run. Defaults to all tiers.

    .PARAMETER DryRun
        Run everything except persisting changes or opening PRs.

    .PARAMETER OutputDirectory
        Directory for report files. Defaults to './avm-report'.

    .PARAMETER ConfigPath
        Path to avmupdater.config.json.

    .OUTPUTS
        PSCustomObject with: updated[], skipped[], rolledBack[], warnings[], reportPath, prUrl.

    .EXAMPLE
        Invoke-AvmUpdate -Path ./infra

    .EXAMPLE
        Invoke-AvmUpdate -Path . -ApprovalMode github -IncludeRisk @('LOW','MEDIUM') -DryRun
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.',

        [Parameter()]
        [string[]]$Exclude = @(),

        [Parameter()]
        [ValidateSet('local', 'github', 'azuredevops')]
        [string]$ApprovalMode = 'local',

        [Parameter()]
        [ValidateSet('LOW', 'MEDIUM', 'HIGH', 'UNKNOWN')]
        [string[]]$IncludeRisk = @('LOW', 'MEDIUM', 'HIGH', 'UNKNOWN'),

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [string]$OutputDirectory = './avm-report',

        [Parameter()]
        [string]$ConfigPath
    )

    $cfg = Get-AvmConfig -ConfigPath $ConfigPath
    if (-not $OutputDirectory) { $OutputDirectory = $cfg.report.outputDirectory }

    Write-Host "`nAvmUpdater — AVM Version Check" -ForegroundColor Cyan
    Write-Host ("─" * 60) -ForegroundColor DarkGray
    if ($DryRun) { Write-Host "[DRY RUN mode — no files will be changed]`n" -ForegroundColor Yellow }

    # Step 1: Scan + version lookup + risk analysis
    Write-Host "Step 1/5: Scanning $Path for AVM references..." -ForegroundColor White
    $plan = Get-AvmUpdatePlan -Path $Path -Exclude $Exclude -ConfigPath $ConfigPath

    # Step 2: Filter by IncludeRisk
    $filteredCandidates = @($plan.candidates | Where-Object { $_.riskTier -in $IncludeRisk })
    $filteredPlan = [PSCustomObject]@{
        candidates   = $filteredCandidates
        lookupFailed = $plan.lookupFailed
        summary      = $plan.summary
    }

    # Step 3: Generate report (always, even on DryRun or zero candidates)
    Write-Host "Step 2/5: Generating report..." -ForegroundColor White
    $reportResult = New-AvmUpdateReport -Plan $filteredPlan -OutputDirectory $OutputDirectory
    Write-Host "  Report: $($reportResult.reportPath)" -ForegroundColor DarkGray

    # Step 4: Zero candidates = no-op
    if ($filteredCandidates.Count -eq 0 -and $plan.lookupFailed.Count -eq 0) {
        Write-Host "`nEverything is up to date. No updates found." -ForegroundColor Green
        Write-Host "Report: $($reportResult.reportPath)" -ForegroundColor DarkGray
        return [PSCustomObject]@{
            updated    = @(); skipped = @(); rolledBack = @(); warnings = @()
            reportPath = $reportResult.reportPath
            jsonPath   = $reportResult.jsonPath
            prUrl      = $null
        }
    }

    Write-Host "  Found $($filteredCandidates.Count) update candidate(s); $($plan.lookupFailed.Count) lookup failure(s)." -ForegroundColor White

    # Step 5: Approval gate
    Write-Host "Step 3/5: Running approval gate ($ApprovalMode)..." -ForegroundColor White
    $approvalResult = Approve-AvmUpdate -Plan $filteredPlan -ReportPath $reportResult.reportPath -ApprovalMode $ApprovalMode -DryRun:$DryRun

    # Step 6: Apply updates (local mode only — github/azuredevops already applied inside approval)
    $updateResult = $null
    if (-not $DryRun -and $ApprovalMode -eq 'local' -and $approvalResult.approvedItems.Count -gt 0) {
        Write-Host "Step 4/5: Applying $($approvalResult.approvedItems.Count) approved update(s)..." -ForegroundColor White
        $updateResult = Update-AvmModuleVersion -ApprovedPlan $approvalResult -DryRun:$DryRun
    } elseif ($DryRun) {
        Write-Host "Step 4/5: [DRY RUN] Skipping file modifications." -ForegroundColor Yellow
    } else {
        Write-Host "Step 4/5: Updates applied inside PR branch (approval mode: $ApprovalMode)." -ForegroundColor DarkGray
    }

    # Step 7: Final summary
    Write-Host "`nStep 5/5: Summary" -ForegroundColor White
    Write-Host ("─" * 60) -ForegroundColor DarkGray

    $updatedItems = @(); if ($updateResult) { $updatedItems = @($updateResult.applied) }
    $rolledBack   = @(); if ($updateResult) { $rolledBack   = @($updateResult.rolledBack) }
    $warningItems = @(); if ($updateResult) { $warningItems = @($updateResult.warnings) }
    $skippedItems = @(); if ($approvalResult -and $approvalResult.skippedItems) { $skippedItems = @($approvalResult.skippedItems) }

    Write-Host "  Updated:     $($updatedItems.Count)" -ForegroundColor Green
    Write-Host "  Skipped:     $($skippedItems.Count)" -ForegroundColor Yellow
    Write-Host "  Rolled back: $($rolledBack.Count)" -ForegroundColor $(if ($rolledBack.Count -gt 0) { 'Red' } else { 'Green' })
    Write-Host "  Warnings:    $($warningItems.Count)" -ForegroundColor $(if ($warningItems.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "  Report:      $($reportResult.reportPath)" -ForegroundColor DarkGray
    if ($approvalResult.prUrl) { Write-Host "  PR URL:      $($approvalResult.prUrl)" -ForegroundColor Cyan }

    if ($rolledBack.Count -gt 0) {
        Write-Warning "Some updates failed validation and were rolled back:"
        foreach ($r in $rolledBack) { Write-Warning "  $($r.item.module): $($r.error)" }
        $global:LASTEXITCODE = 1
    }

    return [PSCustomObject]@{
        updated    = [object[]]$updatedItems
        skipped    = [object[]]$skippedItems
        rolledBack = [object[]]$rolledBack
        warnings   = [object[]]$warningItems
        reportPath = $reportResult.reportPath
        jsonPath   = $reportResult.jsonPath
        prUrl      = $approvalResult.prUrl
    }
}
