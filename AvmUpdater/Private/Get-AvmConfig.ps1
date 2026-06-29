function Get-AvmConfig {
    <#
    .SYNOPSIS
        Loads and validates the avmupdater.config.json, merging with built-in defaults.
    .PARAMETER ConfigPath
        Path to the config file. Searches default locations if not specified.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string]$ConfigPath)

    $defaults = @{
        autoApproveRiskTiers    = @('LOW')
        manualApprovalRiskTiers = @('MEDIUM', 'HIGH', 'UNKNOWN')
        includePaths            = @('**/*.bicep', '**/*.tf')
        excludePaths            = @('**/.terraform/**', '**/node_modules/**', '**/.git/**')
        registry = @{
            httpTimeoutSeconds = 30
            maxRetries         = 3
            retryDelaySeconds  = 2
        }
        report = @{ outputDirectory = './avm-report' }
        github = @{ branchPrefix = 'avm-updates'; splitLowFromHigherRisk = $false }
    }

    if (-not $ConfigPath) {
        $candidates = @(
            (Join-Path $PSScriptRoot '../../config/avmupdater.config.json'),
            (Join-Path $PWD 'config/avmupdater.config.json'),
            (Join-Path $PWD 'avmupdater.config.json')
        )
        $ConfigPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }

    if ($ConfigPath -and (Test-Path $ConfigPath)) {
        $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
        # Shallow merge
        foreach ($key in $json.Keys) { $defaults[$key] = $json[$key] }
    }

    return $defaults
}
