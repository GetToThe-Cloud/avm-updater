function Get-BicepCli {
    <#
    .SYNOPSIS
        Detects the available Bicep CLI once and caches the result for the session.
        Returns a hashtable: { exe, useFileFlag } or $null when no CLI is found.

        Priority:
          1. Standalone 'bicep' binary   → positional file arg  (bicep build file.bicep)
          2. 'az bicep' extension        → --file flag          (az bicep build --file file.bicep)
             Only accepted when 'az bicep version' exits 0, confirming the
             extension is actually installed (not just the az CLI itself).
    #>

    # Return cached result if already probed
    if ($null -ne $script:_BicepCli) {
        # Sentinel: empty hashtable means "probed, nothing found"
        if ($script:_BicepCli.Count -eq 0) { return $null }
        return $script:_BicepCli
    }

    # 1. Standalone bicep binary
    if (Get-Command bicep -ErrorAction SilentlyContinue) {
        $script:_BicepCli = @{ exe = 'bicep'; useFileFlag = $false }
        return $script:_BicepCli
    }

    # 2. az bicep extension — az must exist AND the extension must be installed
    if (Get-Command az -ErrorAction SilentlyContinue) {
        $null = az bicep version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $script:_BicepCli = @{ exe = 'az'; useFileFlag = $true }
            return $script:_BicepCli
        }
        Write-Warning "Azure CLI found but 'az bicep' extension is not installed. Run: az bicep install"
    }

    # Nothing found — cache the "not found" sentinel (empty hashtable)
    $script:_BicepCli = @{}
    return $null
}
