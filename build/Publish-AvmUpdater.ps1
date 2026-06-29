#Requires -Version 7.0
<#
.SYNOPSIS
    Packages and publishes the AvmUpdater module to the PowerShell Gallery.

.DESCRIPTION
    1. Validates the manifest is parseable.
    2. Optionally runs Pester tests (skip with -SkipTests).
    3. Copies the module to a clean staging folder.
    4. Calls Publish-Module targeting PowerShell Gallery.

.PARAMETER ApiKey
    Your PSGallery NuGet API key. Falls back to the PSGALLERY_API_KEY environment variable.

.PARAMETER BumpVersion
    Bump the module version before publishing.
    Valid values: 'patch', 'minor', 'major'.

.PARAMETER SkipTests
    Skip Pester test run.

.PARAMETER WhatIf
    Perform all steps except the actual Publish-Module call.

.EXAMPLE
    ./build/Publish-AvmUpdater.ps1 -BumpVersion patch
    ./build/Publish-AvmUpdater.ps1 -ApiKey 'xxx-yyy' -BumpVersion minor
    ./build/Publish-AvmUpdater.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $ApiKey       = $env:PSGALLERY_API_KEY,
    [ValidateSet('patch','minor','major')]
    [string] $BumpVersion,
    [switch] $SkipTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot   = Resolve-Path "$PSScriptRoot/.."
$moduleRoot = Join-Path $repoRoot 'AvmUpdater'
$psd1Path   = Join-Path $moduleRoot 'AvmUpdater.psd1'
$stagingDir = Join-Path $PSScriptRoot 'staging/AvmUpdater'

# ── 1. Parse manifest ──────────────────────────────────────────────────────────
Write-Host "Reading manifest: $psd1Path" -ForegroundColor Cyan
$manifest = Import-PowerShellDataFile $psd1Path
[System.Version] $currentVersion = $manifest.ModuleVersion
Write-Host "  Current version: $currentVersion"

# ── 2. Bump version ────────────────────────────────────────────────────────────
if ($BumpVersion) {
    $newVersion = switch ($BumpVersion) {
        'patch' { [System.Version]"$($currentVersion.Major).$($currentVersion.Minor).$($currentVersion.Build + 1)" }
        'minor' { [System.Version]"$($currentVersion.Major).$($currentVersion.Minor + 1).0" }
        'major' { [System.Version]"$($currentVersion.Major + 1).0.0" }
    }
    Write-Host "  Bumping version: $currentVersion → $newVersion" -ForegroundColor Yellow
    if ($PSCmdlet.ShouldProcess($psd1Path, "Set ModuleVersion to $newVersion")) {
        Update-ModuleManifest -Path $psd1Path -ModuleVersion $newVersion
    }
    $currentVersion = $newVersion
}

# ── 3. Run Pester tests ────────────────────────────────────────────────────────
if (-not $SkipTests) {
    Write-Host "`nRunning Pester tests…" -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable Pester | Where-Object Version -ge '5.0')) {
        Write-Warning "Pester 5+ not found — install with: Install-Module Pester -MinimumVersion 5.0 -Force"
    } else {
        $pesterConfig = New-PesterConfiguration
        $pesterConfig.Run.Path = Join-Path $repoRoot 'tests'
        $pesterConfig.Run.Exit = $false
        $pesterConfig.Output.Verbosity = 'Normal'
        $result = Invoke-Pester -Configuration $pesterConfig -PassThru
        if ($result.FailedCount -gt 0) {
            throw "$($result.FailedCount) Pester test(s) failed — aborting publish."
        }
        Write-Host "  All $($result.PassedCount) tests passed." -ForegroundColor Green
    }
}

# ── 4. Stage module ────────────────────────────────────────────────────────────
Write-Host "`nStaging module to: $stagingDir" -ForegroundColor Cyan
if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
$null = New-Item $stagingDir -ItemType Directory -Force

# Copy module files (exclude dev artifacts)
$exclude = @('*.Tests.ps1', '*.bak', '.DS_Store')
Get-ChildItem $moduleRoot -Recurse |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules)' } |
    Where-Object { $name = $_.Name; -not ($exclude | Where-Object { $name -like $_ }) } |
    ForEach-Object {
        $dest = $_.FullName.Replace($moduleRoot, $stagingDir)
        if ($_.PSIsContainer) { $null = New-Item $dest -ItemType Directory -Force }
        else { Copy-Item $_.FullName -Destination $dest -Force }
    }

# Verify staged manifest is readable
$null = Import-PowerShellDataFile (Join-Path $stagingDir 'AvmUpdater.psd1')
Write-Host "  Manifest validated in staging." -ForegroundColor Green

# ── 5. Publish ─────────────────────────────────────────────────────────────────
if (-not $ApiKey) {
    throw "No API key provided. Set PSGALLERY_API_KEY or pass -ApiKey."
}

Write-Host "`nPublishing AvmUpdater v$currentVersion to PowerShell Gallery…" -ForegroundColor Cyan
$publishParams = @{
    Path        = $stagingDir
    NuGetApiKey = $ApiKey
    Repository  = 'PSGallery'
    Verbose     = $VerbosePreference -eq 'Continue'
}

if ($PSCmdlet.ShouldProcess('PSGallery', "Publish-Module AvmUpdater v$currentVersion")) {
    Publish-Module @publishParams
    Write-Host "Published! https://www.powershellgallery.com/packages/AvmUpdater/$currentVersion" -ForegroundColor Green
} else {
    Write-Host "[WhatIf] Would publish from: $stagingDir" -ForegroundColor Yellow
}

# ── 6. Clean up staging ────────────────────────────────────────────────────────
Remove-Item $stagingDir -Recurse -Force
Write-Host "Staging cleaned up." -ForegroundColor DarkGray
