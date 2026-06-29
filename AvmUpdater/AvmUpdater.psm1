#Requires -Version 7.0
Set-StrictMode -Version Latest

# Module-level variables
$script:_AvmVersionCache = @{}
$script:_BicepCli        = $null   # populated on first use by Get-BicepCli

# Dot-source all Private helpers first, then Public functions
$Private = @(Get-ChildItem -Path "$PSScriptRoot/Private/*.ps1" -ErrorAction SilentlyContinue)
$Public  = @(Get-ChildItem -Path "$PSScriptRoot/Public/*.ps1"  -ErrorAction SilentlyContinue)

foreach ($file in ($Private + $Public)) {
    try {
        . $file.FullName
    } catch {
        Write-Error "Failed to dot-source '$($file.FullName)': $_"
    }
}

Export-ModuleMember -Function $Public.BaseName
