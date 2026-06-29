function Get-AvmModuleReference {
    <#
    .SYNOPSIS
        Recursively scans a directory for AVM module references in Bicep and Terraform files.

    .DESCRIPTION
        Searches all *.bicep and *.tf files under the specified path for Azure Verified Module
        (AVM) references. Returns normalized objects describing each reference found, including
        ecosystem, category, module name, current version, registry path, file location, and
        line number.

    .PARAMETER Path
        Root directory to scan. Defaults to the current directory.

    .PARAMETER Exclude
        Array of glob patterns to exclude from scanning (e.g. '**/.terraform/**').

    .OUTPUTS
        PSCustomObject[] — one object per unique AVM reference with properties:
        ecosystem, category, group, module, currentVersion, isConstraint, registryPath,
        file, lineNumber, rawMatch.

    .EXAMPLE
        Get-AvmModuleReference -Path ./infra

    .EXAMPLE
        Get-AvmModuleReference -Path . -Exclude @('**/.terraform/**', '**/node_modules/**')
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.',

        [Parameter()]
        [string[]]$Exclude = @()
    )

    # Resolve absolute path
    $rootPath = Resolve-Path -Path $Path -ErrorAction Stop | Select-Object -ExpandProperty Path

    # Bicep patterns
    #   br/public:avm/(res|ptn|utl)/<group>/<module>:<version>
    #   br:mcr.microsoft.com/bicep/avm/(res|ptn|utl)/<group>/<module>:<version>
    $bicepShortPattern = [regex]"'br/public:avm/(res|ptn|utl)/([^/]+)/([^:]+):([^']+)'"
    $bicepFullPattern  = [regex]"'br:mcr\.microsoft\.com/bicep/avm/(res|ptn|utl)/([^/]+)/([^:]+):([^']+)'"

    # Terraform: source line inside a module block + version line
    # We'll parse module blocks and extract source + version
    $tfModulePattern    = [regex]'(?s)module\s+"[^"]+"\s*\{([^}]+)\}'
    $tfSourcePattern    = [regex]'source\s*=\s*"Azure/(avm-(res|ptn|utl)-[^/"]+)/azurerm"'
    $tfVersionPattern   = [regex]'version\s*=\s*"([^"]+)"'

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seen    = [System.Collections.Generic.HashSet[string]]::new()

    # Build exclude filter
    $excludePatterns = $Exclude

    function ShouldExclude([string]$filePath) {
        foreach ($pat in $excludePatterns) {
            if ($filePath -like $pat) { return $true }
        }
        return $false
    }

    # --- Scan Bicep files ---
    Get-ChildItem -Path $rootPath -Recurse -Filter '*.bicep' -File |
        Where-Object { -not (ShouldExclude $_.FullName) } |
        ForEach-Object {
            $file = $_.FullName
            $lines = Get-Content $file
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                $lineNum = $i + 1

                foreach ($pattern in @($bicepShortPattern, $bicepFullPattern)) {
                    $m = $pattern.Match($line)
                    if ($m.Success) {
                        $category    = $m.Groups[1].Value
                        $group       = $m.Groups[2].Value
                        $modName     = $m.Groups[3].Value
                        $version     = $m.Groups[4].Value
                        $regPath     = "bicep/avm/$category/$group/$modName"
                        $dedupeKey   = "$file|$regPath|$version"

                        if ($seen.Add($dedupeKey)) {
                            $results.Add([PSCustomObject]@{
                                ecosystem       = 'bicep'
                                category        = $category
                                group           = $group
                                module          = $modName
                                currentVersion  = $version
                                isConstraint    = $false
                                registryPath    = $regPath
                                file            = $file
                                lineNumber      = $lineNum
                                rawMatch        = $m.Value
                            })
                        }
                    }
                }
            }
        }

    # --- Scan Terraform files ---
    Get-ChildItem -Path $rootPath -Recurse -Filter '*.tf' -File |
        Where-Object { -not (ShouldExclude $_.FullName) } |
        ForEach-Object {
            $file    = $_.FullName
            $content = Get-Content $file -Raw

            $moduleMatches = $tfModulePattern.Matches($content)
            foreach ($mm in $moduleMatches) {
                $body = $mm.Groups[1].Value

                $srcMatch = $tfSourcePattern.Match($body)
                if (-not $srcMatch.Success) { continue }

                $avmModuleName = $srcMatch.Groups[1].Value   # e.g. avm-res-storage-storageaccount
                $regPath       = "Azure/$avmModuleName/azurerm"

                # Determine category from module name
                $category = 'res'
                if ($avmModuleName -match '^avm-(ptn|utl)-') { $category = $Matches[1] }

                $verMatch     = $tfVersionPattern.Match($body)
                $rawVersion   = if ($verMatch.Success) { $verMatch.Groups[1].Value } else { $null }
                $isConstraint = $rawVersion -match '~>|>=|<=|!=|\^|>'

                # Compute lineNumber: find position of source line in file
                $allLines = Get-Content $file
                $lineNum  = 0
                for ($i = 0; $i -lt $allLines.Count; $i++) {
                    if ($allLines[$i] -match [regex]::Escape($srcMatch.Value.Trim())) {
                        $lineNum = $i + 1
                        break
                    }
                }

                $dedupeKey = "$file|$regPath|$rawVersion"
                if ($seen.Add($dedupeKey)) {
                    $results.Add([PSCustomObject]@{
                        ecosystem       = 'terraform'
                        category        = $category
                        group           = $null
                        module          = $avmModuleName
                        currentVersion  = $rawVersion
                        isConstraint    = [bool]$isConstraint
                        registryPath    = $regPath
                        file            = $file
                        lineNumber      = $lineNum
                        rawMatch        = $srcMatch.Value.Trim()
                    })
                }
            }
        }

    return $results.ToArray()
}
