function Get-AvmLatestVersion {
    <#
    .SYNOPSIS
        Fetches all available versions and the latest stable version for a single AVM module.

    .DESCRIPTION
        Queries the appropriate registry (MCR for Bicep, Terraform Registry for Terraform) to
        retrieve all published versions of a module and determine the highest stable (non-preview,
        non-pre-release) semantic version. Caches responses in-memory for the duration of the run.
        On failure, returns an object with status='lookup-failed' without throwing.

    .PARAMETER RegistryPath
        The registry path of the module. For Bicep: 'bicep/avm/res/<group>/<module>'.
        For Terraform: 'Azure/<avmModuleName>/azurerm'.

    .PARAMETER Ecosystem
        The IaC ecosystem — 'bicep' or 'terraform'.

    .PARAMETER Config
        Configuration hashtable (loaded from avmupdater.config.json). Used for timeout/retry.

    .OUTPUTS
        PSCustomObject with: registryPath, ecosystem, latestStable, allVersions[], status.

    .EXAMPLE
        Get-AvmLatestVersion -RegistryPath 'bicep/avm/res/storage/storage-account' -Ecosystem 'bicep'

    .EXAMPLE
        Get-AvmLatestVersion -RegistryPath 'Azure/avm-res-storage-storageaccount/azurerm' -Ecosystem 'terraform'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RegistryPath,

        [Parameter(Mandatory)]
        [ValidateSet('bicep', 'terraform')]
        [string]$Ecosystem,

        [Parameter()]
        [hashtable]$Config = @{}
    )

    # In-memory cache keyed by registryPath+ecosystem (module-level variable, initialized in psm1)
    $cacheKey = "$Ecosystem|$RegistryPath"
    if ($script:_AvmVersionCache.ContainsKey($cacheKey)) {
        Write-Verbose "Cache hit: $cacheKey"
        return $script:_AvmVersionCache[$cacheKey]
    }

    $cfg     = if ($Config.Count) { $Config } else { Get-AvmConfig }
    $timeout = $cfg.registry.httpTimeoutSeconds
    $retries = $cfg.registry.maxRetries
    $delay   = $cfg.registry.retryDelaySeconds

    $result = [PSCustomObject]@{
        registryPath  = $RegistryPath
        ecosystem     = $Ecosystem
        latestStable  = $null
        allVersions   = @()
        status        = 'ok'
    }

    try {
        $rawVersions = Invoke-WithRetry -MaxRetries $retries -DelaySeconds $delay -OperationName "version-lookup:$RegistryPath" -ScriptBlock {
            if ($Ecosystem -eq 'bicep') {
                $url      = "https://mcr.microsoft.com/v2/$RegistryPath/tags/list"
                $response = Invoke-RestMethod -Uri $url -TimeoutSec $timeout -ErrorAction Stop
                return $response.tags
            } else {
                $url      = "https://registry.terraform.io/v1/modules/$RegistryPath/versions"
                $response = Invoke-RestMethod -Uri $url -TimeoutSec $timeout -ErrorAction Stop
                return $response.modules[0].versions | ForEach-Object { $_.version }
            }
        }

        # Filter: keep only valid semver, drop 'latest', preview, alpha, beta, rc
        $stable = $rawVersions |
            Where-Object { $_ -and $_ -notmatch '(latest|preview|alpha|beta|rc)' -and $_ -match '^\d+\.\d+' } |
            Sort-Object { [System.Version]($_ -replace '^v', '') } -Descending

        $result.allVersions  = @($stable)
        $result.latestStable = $stable | Select-Object -First 1
    } catch {
        Write-Warning "Version lookup failed for ${RegistryPath}: $_"
        $result.status = 'lookup-failed'
    }

    $script:_AvmVersionCache[$cacheKey] = $result
    return $result
}
