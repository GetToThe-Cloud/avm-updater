function Get-AvmUpdatePlan {
    <#
    .SYNOPSIS
        Scans a directory, looks up the latest version for each AVM module, performs risk
        analysis, and returns the set of update candidates.

    .DESCRIPTION
        Combines Get-AvmModuleReference, Get-AvmLatestVersion, and Get-AvmUpdateRisk into
        a single pipeline. Returns only modules where an update is available (updateType != none),
        enriched with risk tier, risk reasons, and the interface diff. Also returns a summary
        count by updateType.

    .PARAMETER Path
        Root directory to scan. Defaults to the current directory.

    .PARAMETER Exclude
        Array of glob patterns to exclude.

    .PARAMETER ConfigPath
        Path to the avmupdater.config.json file.

    .OUTPUTS
        PSCustomObject with: candidates[], summary (counts by updateType and risk tier).

    .EXAMPLE
        Get-AvmUpdatePlan -Path ./infra

    .EXAMPLE
        Get-AvmUpdatePlan -Path . -Exclude @('**/.terraform/**') -ConfigPath ./config/avmupdater.config.json
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.',

        [Parameter()]
        [string[]]$Exclude = @(),

        [Parameter()]
        [string]$ConfigPath
    )

    $cfg = Get-AvmConfig -ConfigPath $ConfigPath

    # Build exclude list from args + config
    $allExcludes = @($Exclude) + @($cfg.excludePaths)

    Write-Verbose "Scanning $Path for AVM references..."
    $refs = @(Get-AvmModuleReference -Path $Path -Exclude $allExcludes)

    Write-Verbose "Found $($refs.Count) AVM references. Looking up versions..."

    $candidates  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $lookupFailed = [System.Collections.Generic.List[PSCustomObject]]::new()
    $upToDate     = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($ref in $refs) {
        $lookup = Get-AvmLatestVersion -RegistryPath $ref.registryPath -Ecosystem $ref.ecosystem -Config $cfg

        if ($lookup.status -eq 'lookup-failed') {
            $lookupFailed.Add([PSCustomObject]@{
                reference    = $ref
                status       = 'lookup-failed'
                riskTier     = 'UNKNOWN'
                riskReasons  = @("Version lookup failed — could not reach registry for $($ref.registryPath)")
            })
            continue
        }

        $latestStable = $lookup.latestStable
        if (-not $latestStable) {
            Write-Warning "No stable version found for $($ref.registryPath)"
            continue
        }

        # For constraint refs, compare whether latestStable exceeds the constraint
        if ($ref.isConstraint) {
            $updateType = 'constraint'
            $note = "Constraint ref '~>' — latestStable '$latestStable' may exceed constraint '$($ref.currentVersion)'. Recommend pinning to '$latestStable'."
        } else {
            $updateType = Get-AvmUpdateType -Current $ref.currentVersion -Target $latestStable
        }

        if ($updateType -eq 'none') {
            $upToDate.Add([PSCustomObject]@{
                ecosystem      = $ref.ecosystem
                module         = $ref.module
                registryPath   = $ref.registryPath
                file           = $ref.file
                lineNumber     = $ref.lineNumber
                currentVersion = $ref.currentVersion
                latestStable   = $latestStable
                status         = 'up-to-date'
            })
            continue
        }

        # Enrich with risk analysis
        $risk = Get-AvmUpdateRisk -Reference $ref -TargetVersion $latestStable

        $candidates.Add([PSCustomObject]@{
            reference       = $ref
            ecosystem       = $ref.ecosystem
            module          = $ref.module
            registryPath    = $ref.registryPath
            file            = $ref.file
            lineNumber      = $ref.lineNumber
            currentVersion  = $ref.currentVersion
            latestStable    = $latestStable
            updateType      = $updateType
            isConstraint    = $ref.isConstraint
            riskTier        = $risk.riskTier
            riskReasons     = $risk.riskReasons
            interfaceDiff   = $risk.interfaceDiff
            changelogLines  = $risk.changelogLines
            status          = 'pending'
            note            = if ($ref.isConstraint) { $note } else { $null }
        })
    }

    # Build summary
    $allItems = @($candidates) + @($lookupFailed)
    $summary = [PSCustomObject]@{
        scannedAt    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        pathsScanned = @($Path)
        totalRefs    = $refs.Count
        totalUpdates = $candidates.Count
        totalUpToDate = $upToDate.Count
        byUpdateType = @{
            major      = @($candidates | Where-Object updateType -eq 'major').Count
            minor      = @($candidates | Where-Object updateType -eq 'minor').Count
            patch      = @($candidates | Where-Object updateType -eq 'patch').Count
            constraint = @($candidates | Where-Object updateType -eq 'constraint').Count
        }
        byRiskTier = @{
            HIGH    = @($allItems | Where-Object riskTier -eq 'HIGH').Count
            MEDIUM  = @($allItems | Where-Object riskTier -eq 'MEDIUM').Count
            LOW     = @($allItems | Where-Object riskTier -eq 'LOW').Count
            UNKNOWN = @($allItems | Where-Object riskTier -eq 'UNKNOWN').Count
        }
        lookupFailed = $lookupFailed.Count
    }

    return [PSCustomObject]@{
        candidates   = $candidates.ToArray()
        upToDate     = $upToDate.ToArray()
        lookupFailed = $lookupFailed.ToArray()
        summary      = $summary
    }
}
