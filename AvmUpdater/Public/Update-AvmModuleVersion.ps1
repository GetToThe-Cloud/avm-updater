function Update-AvmModuleVersion {
    <#
    .SYNOPSIS
        Applies approved AVM version bumps, validates with bicep build/lint or terraform
        init/validate/plan, and rolls back per-file failures.

    .DESCRIPTION
        For each item in the approved plan:
        1. Backs up the original file.
        2. Rewrites ONLY the version token at the recorded file:line.
        3. Runs validation (bicep build+lint or terraform init+validate+plan).
        4. If validation fails, restores the backup (rollback).
        5. Parses terraform plan output for DESTROY/REPLACE actions and flags them as WARN.
        Updates are independent — one failure does not block others. Respects -DryRun.

    .PARAMETER ApprovedPlan
        The approved update items from Approve-AvmUpdate.

    .PARAMETER DryRun
        Edit a temp copy and validate without persisting changes.

    .OUTPUTS
        PSCustomObject with: applied[], rolledBack[], warnings[], isConsistent (bool).

    .EXAMPLE
        $approved = Approve-AvmUpdate -Plan $plan -ApprovalMode local
        Update-AvmModuleVersion -ApprovedPlan $approved

    .EXAMPLE
        Update-AvmModuleVersion -ApprovedPlan $approved -DryRun
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ApprovedPlan,

        [Parameter()]
        [switch]$DryRun
    )

    $applied    = [System.Collections.Generic.List[PSCustomObject]]::new()
    $rolledBack = [System.Collections.Generic.List[PSCustomObject]]::new()
    $warnings   = [System.Collections.Generic.List[PSCustomObject]]::new()

    $items = @($ApprovedPlan.approvedItems)
    if ($items.Count -eq 0) {
        Write-Verbose "No approved items to update."
        return [PSCustomObject]@{ applied = @(); rolledBack = @(); warnings = @(); isConsistent = $true }
    }

    foreach ($item in $items) {
        $file        = $item.file
        $lineIndex   = $item.lineNumber - 1
        $oldVersion  = $item.currentVersion
        $newVersion  = $item.latestStable
        $ecosystem   = $item.ecosystem

        # Backup
        $backupPath = "$file.avmbak"
        $origLines  = Get-Content $file -Raw

        # Compute working file (DryRun = temp copy)
        $workFile = if ($DryRun) {
            $tmp = [System.IO.Path]::GetTempFileName() + (Split-Path $file -Extension)
            Set-Content -Path $tmp -Value $origLines -Encoding UTF8 -NoNewline
            $tmp
        } else {
            $file
        }

        if (-not $DryRun) {
            Set-Content -Path $backupPath -Value $origLines -Encoding UTF8 -NoNewline
        }

        # Perform the line-level rewrite
        try {
            $lines = Get-Content $workFile
            $targetLine = $lines[$lineIndex]

            $newLine = if ($ecosystem -eq 'bicep') {
                # Replace :oldVersion' with :newVersion'
                $targetLine -replace "`:$([regex]::Escape($oldVersion))'", ":$newVersion'"
            } else {
                # Replace version = "oldVersion" with version = "newVersion"
                $targetLine -replace "version\s*=\s*`"$([regex]::Escape($oldVersion))`"", "version = `"$newVersion`""
            }

            if ($newLine -eq $targetLine) {
                Write-Warning "No version token found at ${file}:$($item.lineNumber) — skipping."
                if ($DryRun -and (Test-Path $workFile)) { Remove-Item $workFile -Force }
                continue
            }

            $lines[$lineIndex] = $newLine
            Set-Content -Path $workFile -Value $lines -Encoding UTF8
        } catch {
            Write-Warning "Failed to edit ${file}: $_"
            if ($DryRun -and (Test-Path $workFile)) { Remove-Item $workFile -Force }
            $rolledBack.Add([PSCustomObject]@{ item = $item; error = $_.ToString() })
            continue
        }

        # Validate
        $validationResult = Invoke-AvmValidation -FilePath $workFile -Ecosystem $ecosystem

        switch ($validationResult.outcome) {
            'PASS' {
                if (-not $DryRun) { Remove-Item $backupPath -Force -ErrorAction SilentlyContinue }
                $applied.Add([PSCustomObject]@{ item = $item; outcome = 'PASS'; details = $validationResult.output })
                Write-Verbose "PASS: $($item.module) $oldVersion → $newVersion"
            }
            'WARN' {
                if (-not $DryRun) { Remove-Item $backupPath -Force -ErrorAction SilentlyContinue }
                $applied.Add([PSCustomObject]@{ item = $item; outcome = 'WARN'; details = $validationResult.output })
                $warnings.Add([PSCustomObject]@{ item = $item; reason = $validationResult.warnReason })
                Write-Warning "WARN: $($item.module) — $($validationResult.warnReason)"
            }
            'FAIL' {
                # Roll back
                if (-not $DryRun) {
                    Copy-Item $backupPath $file -Force
                    Remove-Item $backupPath -Force -ErrorAction SilentlyContinue
                }
                $rolledBack.Add([PSCustomObject]@{ item = $item; error = $validationResult.output })
                Write-Warning "FAIL: $($item.module) — rolled back. Error: $($validationResult.output)"
            }
            'SKIP' {
                # Validation skipped (no CLI available) — accept the change with a warning
                if (-not $DryRun) { Remove-Item $backupPath -Force -ErrorAction SilentlyContinue }
                $applied.Add([PSCustomObject]@{ item = $item; outcome = 'SKIP'; details = $validationResult.output })
                $warnings.Add([PSCustomObject]@{ item = $item; reason = $validationResult.warnReason })
                Write-Warning "SKIP validation: $($item.module) — $($validationResult.warnReason)"
            }
        }

        if ($DryRun -and (Test-Path $workFile)) { Remove-Item $workFile -Force }
    }

    $isConsistent = $rolledBack.Count -eq 0

    return [PSCustomObject]@{
        applied      = $applied.ToArray()
        rolledBack   = $rolledBack.ToArray()
        warnings     = $warnings.ToArray()
        isConsistent = $isConsistent
    }
}

function Invoke-AvmValidation {
    <#
    .SYNOPSIS
        Runs bicep build+lint or terraform init+validate+plan on the given file/directory.
        Returns outcome (PASS|WARN|FAIL), output, and warnReason.
    #>
    [CmdletBinding()]
    param(
        [string]$FilePath,
        [string]$Ecosystem
    )

    $outcome    = 'PASS'
    $output     = ''
    $warnReason = $null

    try {
        if ($Ecosystem -eq 'bicep') {
            $cli = Get-BicepCli
            if (-not $cli) {
                Write-Warning "No Bicep CLI found — skipping validation for ${FilePath}. Install 'bicep' or run 'az bicep install'."
                return [PSCustomObject]@{ outcome = 'SKIP'; output = 'No Bicep CLI available'; warnReason = 'Bicep validation skipped (no CLI)' }
            }

            # standalone 'bicep' uses positional args; 'az bicep' requires --file
            if ($cli.useFileFlag) {
                $buildOut = & az bicep build --file $FilePath 2>&1
                if ($LASTEXITCODE -ne 0) {
                    return [PSCustomObject]@{ outcome = 'FAIL'; output = $buildOut -join "`n"; warnReason = $null }
                }
                $lintOut = & az bicep lint --file $FilePath 2>&1
                if ($LASTEXITCODE -ne 0) {
                    return [PSCustomObject]@{ outcome = 'FAIL'; output = $lintOut -join "`n"; warnReason = $null }
                }
            } else {
                $buildOut = & bicep build $FilePath 2>&1
                if ($LASTEXITCODE -ne 0) {
                    return [PSCustomObject]@{ outcome = 'FAIL'; output = $buildOut -join "`n"; warnReason = $null }
                }
                $lintOut = & bicep lint $FilePath 2>&1
                if ($LASTEXITCODE -ne 0) {
                    return [PSCustomObject]@{ outcome = 'FAIL'; output = $lintOut -join "`n"; warnReason = $null }
                }
            }
            $output = ($buildOut + $lintOut) -join "`n"
        } elseif ($Ecosystem -eq 'terraform') {
            $tfDir = Split-Path $FilePath -Parent

            $initOut = terraform -chdir=$tfDir init -upgrade 2>&1
            if ($LASTEXITCODE -ne 0) {
                return [PSCustomObject]@{ outcome = 'FAIL'; output = $initOut -join "`n"; warnReason = $null }
            }

            $validateOut = terraform -chdir=$tfDir validate 2>&1
            if ($LASTEXITCODE -ne 0) {
                return [PSCustomObject]@{ outcome = 'FAIL'; output = $validateOut -join "`n"; warnReason = $null }
            }

            $planOut = terraform -chdir=$tfDir plan -detailed-exitcode -no-color 2>&1
            $planText = $planOut -join "`n"

            # exit code 1 = error, 2 = changes (acceptable), 0 = no changes
            if ($LASTEXITCODE -eq 1) {
                return [PSCustomObject]@{ outcome = 'FAIL'; output = $planText; warnReason = $null }
            }

            # Check for DESTROY/REPLACE in plan
            if ($planText -match '(?i)(must be replaced|will be destroyed|# .+ will be destroyed|# .+ must be replaced)') {
                $outcome    = 'WARN'
                $warnReason = "Terraform plan includes DESTROY or REPLACE actions — manual review required."
            }
            $output = $planText
        }
    } catch {
        return [PSCustomObject]@{ outcome = 'FAIL'; output = $_.ToString(); warnReason = $null }
    }

    return [PSCustomObject]@{ outcome = $outcome; output = $output; warnReason = $warnReason }
}
