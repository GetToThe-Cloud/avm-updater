function Approve-AvmUpdate {
    <#
    .SYNOPSIS
        Approval gate for AVM updates — supports local interactive, GitHub PR, and Azure
        DevOps PR modes.

    .DESCRIPTION
        Filters the update plan through the configured approval policy:
        - autoApproveRiskTiers (default: LOW) proceed without sign-off.
        - manualApprovalRiskTiers (default: MEDIUM, HIGH, UNKNOWN) require human action.

        In 'local' mode, prompts interactively via Read-Host.
        In 'github' mode, creates a branch, applies updates, commits, pushes, and opens a PR.
          Merging the PR is the approval.
        In 'azuredevops' mode, same flow via 'az repos pr create'.
        Never auto-merges. Returns the approved subset plus an audit record.

    .PARAMETER Plan
        The enriched plan from Get-AvmUpdatePlan.

    .PARAMETER ReportPath
        Path to the generated Markdown report (used as PR body in github/azuredevops modes).

    .PARAMETER ApprovalMode
        Approval mechanism: 'local', 'github', or 'azuredevops'. Defaults to 'local'.

    .PARAMETER DryRun
        Show what would be asked/done without making changes or opening PRs.

    .OUTPUTS
        PSCustomObject with: approvedItems[], skippedItems[], auditRecord, prUrl.

    .EXAMPLE
        $plan = Get-AvmUpdatePlan -Path ./infra
        Approve-AvmUpdate -Plan $plan -ApprovalMode local

    .EXAMPLE
        Approve-AvmUpdate -Plan $plan -ReportPath ./avm-report/avm-update-report.md -ApprovalMode github
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Plan,

        [Parameter()]
        [string]$ReportPath,

        [Parameter()]
        [ValidateSet('local', 'github', 'azuredevops')]
        [string]$ApprovalMode = 'local',

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [string]$WorkingDirectory = '.'
    )

    $cfg              = Get-AvmConfig
    $autoTiers        = @($cfg.autoApproveRiskTiers)
    $manualTiers      = @($cfg.manualApprovalRiskTiers)

    $approved = [System.Collections.Generic.List[PSCustomObject]]::new()
    $skipped  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $prUrl    = $null

    $auditRecord = [PSCustomObject]@{
        mode          = $ApprovalMode
        timestamp     = (Get-Date -Format 'o')
        approvedItems = @()
        skippedItems  = @()
        actor         = $env:USERNAME ?? $env:USER ?? 'unknown'
    }

    # Split into auto and manual tiers
    $autoItems   = @($Plan.candidates | Where-Object { $_.riskTier -in $autoTiers })
    $manualItems = @($Plan.candidates | Where-Object { $_.riskTier -in $manualTiers })

    # Auto-approve items
    foreach ($item in $autoItems) { $approved.Add($item) }

    switch ($ApprovalMode) {
        'local' {
            if ($DryRun) {
                Write-Host "`n[DRY RUN] Would auto-approve $($autoItems.Count) LOW item(s)." -ForegroundColor Cyan
                Write-Host "[DRY RUN] Would prompt for $($manualItems.Count) MEDIUM/HIGH/UNKNOWN item(s).`n" -ForegroundColor Cyan
                foreach ($item in $manualItems) {
                    Write-Host "  [DRY RUN] Prompt: Approve $($item.module) $($item.currentVersion) → $($item.latestStable) [$($item.riskTier)]?" -ForegroundColor Yellow
                }
                $approved.Clear()
                break
            }

            if ($manualItems.Count -gt 0) {
                Write-Host "`nAVM Update Approval — Manual Review Required" -ForegroundColor Cyan
                Write-Host ("─" * 60) -ForegroundColor DarkGray
                Write-Host "Auto-approved (LOW): $($autoItems.Count) item(s)" -ForegroundColor Green
                $upToDateCount = if ($Plan.PSObject.Properties['upToDate'] -and $Plan.upToDate) { @($Plan.upToDate).Count } else { 0 }
                if ($upToDateCount -gt 0) {
                    Write-Host "Already up to date:  $upToDateCount module(s)" -ForegroundColor Green
                }
                Write-Host "Needs review: $($manualItems.Count) item(s)`n" -ForegroundColor Yellow

                # Show summary table
                Write-Host (" {0,-35} {1,-12} {2,-10} {3,-8} {4}" -f 'Module','Current','Latest','Jump','Risk') -ForegroundColor White
                Write-Host ("-" * 80) -ForegroundColor DarkGray
                foreach ($item in $manualItems) {
                    $color = switch ($item.riskTier) { 'HIGH' { 'Red' } 'MEDIUM' { 'Yellow' } default { 'White' } }
                    Write-Host (" {0,-35} {1,-12} {2,-10} {3,-8} {4}" -f $item.module, $item.currentVersion, $item.latestStable, $item.updateType, $item.riskTier) -ForegroundColor $color
                }

                # Show auto-approved LOW items
                foreach ($item in $autoItems) {
                    Write-Host (" {0,-35} {1,-12} {2,-10} {3,-8} {4}" -f $item.module, $item.currentVersion, $item.latestStable, $item.updateType, $item.riskTier) -ForegroundColor Green
                }

                # Show up-to-date modules in green
                $upToDateItems = @()
                if ($Plan.PSObject.Properties['upToDate'] -and $Plan.upToDate) {
                    $upToDateItems = @($Plan.upToDate)
                }
                foreach ($item in $upToDateItems) {
                    Write-Host (" {0,-35} {1,-12} {2,-10} {3,-8} {4}" -f $item.module, $item.currentVersion, $item.currentVersion, 'none', 'up-to-date') -ForegroundColor Green
                }
                Write-Host ""

                $bulkChoice = Read-Host "Approve all LOW+MEDIUM automatically? [y=yes all LOW, m=review each, n=skip all] (default: m)"
                if (-not $bulkChoice) { $bulkChoice = 'm' }

                foreach ($item in $manualItems) {
                    $decision = switch ($bulkChoice.ToLower()) {
                        'y' { if ($item.riskTier -in @('LOW','MEDIUM')) { 'approve' } else { 'review' } }
                        'n' { 'skip' }
                        default { 'review' }
                    }

                    if ($decision -eq 'review') {
                        Write-Host "`nReviewing: $($item.module) [$($item.riskTier)]" -ForegroundColor Cyan
                        Write-Host "  Version : $($item.currentVersion) → $($item.latestStable) ($($item.updateType))" -ForegroundColor White
                        Write-Host "  File    : $($item.file):$($item.lineNumber)" -ForegroundColor DarkGray

                        if ($item.riskReasons.Count -gt 0) {
                            Write-Host "  Risk    :" -ForegroundColor Yellow
                            foreach ($r in $item.riskReasons) { Write-Host "    • $r" -ForegroundColor Yellow }
                        }

                        $diff = $item.interfaceDiff
                        if ($diff -and $diff.available) {
                            if ($diff.removedInputs.Count)  { Write-Host "  Diff    : Removed inputs: $($diff.removedInputs -join ', ')"  -ForegroundColor Red }
                            if ($diff.addedRequired.Count)  { Write-Host "  Diff    : Added required: $($diff.addedRequired -join ', ')"  -ForegroundColor Red }
                            if ($diff.typeChanged.Count)    { Write-Host "  Diff    : Type changes:   $($diff.typeChanged -join ', ')"    -ForegroundColor Yellow }
                            if ($diff.removedOutputs.Count) { Write-Host "  Diff    : Removed outputs: $($diff.removedOutputs -join ', ')" -ForegroundColor Red }
                            if ($diff.addedOptional.Count)  { Write-Host "  Diff    : Added optional: $($diff.addedOptional -join ', ')"  -ForegroundColor Green }
                        } elseif (-not $diff -or -not $diff.available) {
                            Write-Host "  Diff    : (unavailable — review manually)" -ForegroundColor DarkGray
                        }

                        if ($item.changelogLines.Count -gt 0) {
                            Write-Host "  Changes :" -ForegroundColor White
                            foreach ($cl in $item.changelogLines | Select-Object -First 5) {
                                Write-Host "    • $cl" -ForegroundColor DarkYellow
                            }
                        } else {
                            Write-Host "  Changes : (no changelog evidence found)" -ForegroundColor DarkGray
                        }

                        $choice = Read-Host "  Approve this update? [y/n]"
                        $decision = if ($choice -eq 'y') { 'approve' } else { 'skip' }
                    }

                    if ($decision -eq 'approve') { $approved.Add($item) }
                    else { $skipped.Add($item) }
                }
            }
        }

        'github' {
            $token = $env:GITHUB_TOKEN
            if (-not $token) { throw "GITHUB_TOKEN environment variable is required for github approval mode." }

            $branchName = "$($cfg.github.branchPrefix)/$(Get-Date -Format 'yyyyMMdd-HHmm')"

            if ($DryRun) {
                Write-Host "[DRY RUN] Would create branch '$branchName', apply updates, and open a PR." -ForegroundColor Cyan
                break
            }

            # Apply all approved + manual items to a branch, then open PR
            # All candidates go in — PR merge is the approval gate
            foreach ($item in $manualItems) { $approved.Add($item) }

            # Resolve report path to absolute before changing directory
            $absReportPath = if ($ReportPath) {
                (Resolve-Path $ReportPath -ErrorAction SilentlyContinue)?.Path ?? $ReportPath
            } else { $null }

            # Apply file updates now (file paths are absolute — works from any directory)
            $updateResult = Update-AvmModuleVersion -ApprovedPlan ([PSCustomObject]@{ approvedItems = $approved.ToArray() })

            Push-Location $WorkingDirectory
            try {
                Write-Verbose "Creating branch: $branchName"
                git checkout -b $branchName 2>&1 | Write-Verbose

                git add -A 2>&1 | Write-Verbose
                git commit -m "chore(avm): update AVM module versions [$(Get-Date -Format 'yyyy-MM-dd')]" 2>&1 | Write-Verbose

                $pushOutput = git push origin $branchName 2>&1
                Write-Verbose ($pushOutput -join "`n")
                if ($LASTEXITCODE -ne 0) {
                    throw "git push failed: $($pushOutput -join ' ')"
                }

                $reportBody = if ($absReportPath -and (Test-Path $absReportPath)) { Get-Content $absReportPath -Raw } else { "AVM update plan — see artifacts." }

                # Create PR — labels are intentionally omitted to avoid failures on repos
                # that do not have the label pre-created.
                if (Get-Command gh -ErrorAction SilentlyContinue) {
                    $prUrl = gh pr create --title "chore(avm): update AVM module versions" --body $reportBody 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "gh pr create failed: $($prUrl -join ' ')"
                        $prUrl = $null
                    }
                } else {
                    Write-Warning "gh CLI not found; PR creation skipped. Push to '$branchName' succeeded."
                }
            } finally {
                Pop-Location
            }
        }

        'azuredevops' {
            $token = $env:SYSTEM_ACCESSTOKEN ?? $env:AZURE_DEVOPS_EXT_PAT
            if (-not $token) { throw "SYSTEM_ACCESSTOKEN or AZURE_DEVOPS_EXT_PAT is required for azuredevops approval mode." }

            $branchName = "$($cfg.github.branchPrefix)/$(Get-Date -Format 'yyyyMMdd-HHmm')"

            if ($DryRun) {
                Write-Host "[DRY RUN] Would create branch '$branchName' and open an Azure DevOps PR." -ForegroundColor Cyan
                break
            }

            foreach ($item in $manualItems) { $approved.Add($item) }

            $absReportPath = if ($ReportPath) {
                (Resolve-Path $ReportPath -ErrorAction SilentlyContinue)?.Path ?? $ReportPath
            } else { $null }

            Push-Location $WorkingDirectory
            try {
                git checkout -b $branchName 2>&1 | Write-Verbose
                $null = Update-AvmModuleVersion -ApprovedPlan ([PSCustomObject]@{ approvedItems = $approved.ToArray() })
                git add -A 2>&1 | Write-Verbose
                git commit -m "chore(avm): update AVM module versions [$(Get-Date -Format 'yyyy-MM-dd')]" 2>&1 | Write-Verbose

                $pushOutput = git push origin $branchName 2>&1
                Write-Verbose ($pushOutput -join "`n")
                if ($LASTEXITCODE -ne 0) {
                    throw "git push failed: $($pushOutput -join ' ')"
                }

                $reportBody = if ($absReportPath -and (Test-Path $absReportPath)) { Get-Content $absReportPath -Raw } else { "AVM update plan." }

                if (Get-Command az -ErrorAction SilentlyContinue) {
                    $env:AZURE_DEVOPS_EXT_PAT = $token
                    $prUrl = az repos pr create --title "chore(avm): update AVM module versions" --description $reportBody --source-branch $branchName 2>&1
                } else {
                    Write-Warning "az CLI not found; PR creation skipped."
                }
            } finally {
                Pop-Location
            }
        }
    }

    $auditRecord.approvedItems = $approved.ToArray()
    $auditRecord.skippedItems  = $skipped.ToArray()

    return [PSCustomObject]@{
        approvedItems = $approved.ToArray()
        skippedItems  = $skipped.ToArray()
        auditRecord   = $auditRecord
        prUrl         = $prUrl
    }
}
