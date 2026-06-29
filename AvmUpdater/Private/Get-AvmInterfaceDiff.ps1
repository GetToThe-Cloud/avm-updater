function Get-AvmInterfaceDiff {
    <#
    .SYNOPSIS
        Compares the module interface (params/outputs) between two versions of an AVM module.
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$Reference,
        [string]$TargetVersion
    )

    $diff = [PSCustomObject]@{
        available        = $false
        addedRequired    = @()   # NEW required inputs (no default) — BREAKING
        removedInputs    = @()   # Removed/renamed params — BREAKING
        typeChanged      = @()   # Type changes — BREAKING
        addedOptional    = @()   # New optional inputs — non-breaking
        removedOutputs   = @()   # Removed/renamed outputs — BREAKING
        addedOutputs     = @()   # New outputs — non-breaking
        rawError         = $null
    }

    try {
        if ($Reference.ecosystem -eq 'bicep') {
            $diff = Get-BicepInterfaceDiff -Reference $Reference -TargetVersion $TargetVersion
        } elseif ($Reference.ecosystem -eq 'terraform') {
            $diff = Get-TerraformInterfaceDiff -Reference $Reference -TargetVersion $TargetVersion
        }
    } catch {
        $diff.rawError = $_.ToString()
        Write-Verbose "Interface diff unavailable for $($Reference.registryPath): $_"
    }

    return $diff
}

function Get-BicepInterfaceDiff {
    [CmdletBinding()]
    param([PSCustomObject]$Reference, [string]$TargetVersion)

    $diff = [PSCustomObject]@{
        available = $false; addedRequired = @(); removedInputs = @()
        typeChanged = @(); addedOptional = @(); removedOutputs = @()
        addedOutputs = @(); rawError = $null
    }

    # Fetch main.bicep from GitHub bicep-registry-modules for both versions
    $baseUrl = "https://raw.githubusercontent.com/Azure/bicep-registry-modules"
    $modPath = "avm/$($Reference.category)/$($Reference.group)/$($Reference.module)/main.bicep"

    # Build git tags: typically 'avm/<category>/<group>/<module>/<version>'
    $tagPrefix = "avm/$($Reference.category)/$($Reference.group)/$($Reference.module)"
    $curTag    = "$tagPrefix/$($Reference.currentVersion)"
    $tgtTag    = "$tagPrefix/$TargetVersion"

    $curContent = $null
    $tgtContent = $null
    try {
        $curContent = Invoke-RestMethod -Uri "$baseUrl/$curTag/$modPath" -TimeoutSec 15 -ErrorAction Stop
    } catch { Write-Verbose "Could not fetch bicep current interface: $_" }
    try {
        $tgtContent = Invoke-RestMethod -Uri "$baseUrl/$tgtTag/$modPath" -TimeoutSec 15 -ErrorAction Stop
    } catch { Write-Verbose "Could not fetch bicep target interface: $_" }

    if (-not $curContent -or -not $tgtContent) { return $diff }
    $diff.available = $true

    $curParams  = ParseBicepParams -Content $curContent
    $tgtParams  = ParseBicepParams -Content $tgtContent
    $curOutputs = ParseBicepOutputs -Content $curContent
    $tgtOutputs = ParseBicepOutputs -Content $tgtContent

    # Required param added (no default in target, absent in current)
    foreach ($p in $tgtParams.Keys) {
        if (-not $curParams.ContainsKey($p) -and -not $tgtParams[$p].hasDefault) {
            $diff.addedRequired += $p
        } elseif (-not $curParams.ContainsKey($p) -and $tgtParams[$p].hasDefault) {
            $diff.addedOptional += $p
        } elseif ($curParams.ContainsKey($p) -and $tgtParams[$p].type -ne $curParams[$p].type) {
            $diff.typeChanged += "$p (${$curParams[$p].type} -> ${$tgtParams[$p].type})"
        }
    }
    # Removed params
    foreach ($p in $curParams.Keys) {
        if (-not $tgtParams.ContainsKey($p)) { $diff.removedInputs += $p }
    }
    # Outputs
    foreach ($o in $curOutputs) {
        if ($o -notin $tgtOutputs) { $diff.removedOutputs += $o }
    }
    foreach ($o in $tgtOutputs) {
        if ($o -notin $curOutputs) { $diff.addedOutputs += $o }
    }

    return $diff
}

function ParseBicepParams {
    param([string]$Content)
    $params = @{}
    $pattern = [regex]"^@(description|metadata).*\n*param\s+(\w+)\s+(\S+)(\s*=\s*.+)?$"
    $simplePattern = [regex]"^param\s+(\w+)\s+(\S+)(\s*=\s*.+)?$"
    foreach ($m in $simplePattern.Matches($Content)) {
        $name       = $m.Groups[1].Value
        $type       = $m.Groups[2].Value
        $hasDefault = $m.Groups[3].Success
        $params[$name] = @{ type = $type; hasDefault = $hasDefault }
    }
    return $params
}

function ParseBicepOutputs {
    param([string]$Content)
    $outputs = @()
    $pattern = [regex]"^output\s+(\w+)\s+"
    foreach ($m in $pattern.Matches($Content)) {
        $outputs += $m.Groups[1].Value
    }
    return $outputs
}

function Get-TerraformInterfaceDiff {
    [CmdletBinding()]
    param([PSCustomObject]$Reference, [string]$TargetVersion)

    $diff = [PSCustomObject]@{
        available = $false; addedRequired = @(); removedInputs = @()
        typeChanged = @(); addedOptional = @(); removedOutputs = @()
        addedOutputs = @(); rawError = $null
    }

    # Repo: Azure/terraform-azurerm-<avmModuleName> or Azure/<avmModuleName>
    $repoName = $Reference.module -replace '^avm-', 'terraform-azurerm-avm-'
    $baseUrl  = "https://raw.githubusercontent.com/Azure/$repoName"

    $curVars = $null; $tgtVars = $null
    $curOuts = $null; $tgtOuts = $null
    try {
        $curVars = Invoke-RestMethod -Uri "$baseUrl/v$($Reference.currentVersion)/variables.tf" -TimeoutSec 15 -ErrorAction Stop
        $tgtVars = Invoke-RestMethod -Uri "$baseUrl/v$TargetVersion/variables.tf" -TimeoutSec 15 -ErrorAction Stop
        $curOuts = Invoke-RestMethod -Uri "$baseUrl/v$($Reference.currentVersion)/outputs.tf" -TimeoutSec 15 -ErrorAction Stop
        $tgtOuts = Invoke-RestMethod -Uri "$baseUrl/v$TargetVersion/outputs.tf" -TimeoutSec 15 -ErrorAction Stop
    } catch { Write-Verbose "Could not fetch terraform interface: $_"; return $diff }

    $diff.available = $true
    $curVarMap = ParseTfVariables -Content $curVars
    $tgtVarMap = ParseTfVariables -Content $tgtVars
    $curOutMap = ParseTfOutputs  -Content $curOuts
    $tgtOutMap = ParseTfOutputs  -Content $tgtOuts

    foreach ($v in $tgtVarMap.Keys) {
        if (-not $curVarMap.ContainsKey($v)) {
            if (-not $tgtVarMap[$v].hasDefault) { $diff.addedRequired += $v }
            else { $diff.addedOptional += $v }
        } elseif ($curVarMap[$v].type -ne $tgtVarMap[$v].type) {
            $diff.typeChanged += "$v ($($curVarMap[$v].type) -> $($tgtVarMap[$v].type))"
        }
    }
    foreach ($v in $curVarMap.Keys) {
        if (-not $tgtVarMap.ContainsKey($v)) { $diff.removedInputs += $v }
    }
    foreach ($o in $curOutMap) { if ($o -notin $tgtOutMap) { $diff.removedOutputs += $o } }
    foreach ($o in $tgtOutMap) { if ($o -notin $curOutMap) { $diff.addedOutputs += $o } }

    return $diff
}

function ParseTfVariables {
    param([string]$Content)
    $vars = @{}
    $blockPattern = [regex]'(?s)variable\s+"(\w+)"\s*\{([^}]+)\}'
    foreach ($m in $blockPattern.Matches($Content)) {
        $name       = $m.Groups[1].Value
        $body       = $m.Groups[2].Value
        $typeMatch  = [regex]::Match($body, 'type\s*=\s*(\S+)')
        $type       = if ($typeMatch.Success) { $typeMatch.Groups[1].Value } else { 'any' }
        $hasDefault = $body -match 'default\s*='
        $vars[$name] = @{ type = $type; hasDefault = $hasDefault }
    }
    return $vars
}

function ParseTfOutputs {
    param([string]$Content)
    $outputs = @()
    $pattern = [regex]'output\s+"(\w+)"\s*\{'
    foreach ($m in $pattern.Matches($Content)) { $outputs += $m.Groups[1].Value }
    return $outputs
}
