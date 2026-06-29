# AvmUpdater — Repository-wide Copilot instructions

## Project overview

**AvmUpdater** is a PowerShell 7 module that:
1. Scans Bicep (`.bicep`) and Terraform (`.tf`) files for Azure Verified Module (AVM) references.
2. Queries MCR (for Bicep) and the Terraform Registry to find the latest stable version.
3. Performs a breaking-change risk analysis (interface diff + changelog + semver).
4. Generates a Markdown report and a machine-readable JSON manifest.
5. Requires **explicit approval** (local interactive, GitHub PR, or Azure DevOps PR) before applying any changes.
6. Applies version bumps with per-file rollback on validation failure.

## Architecture

```
AvmUpdater/
  AvmUpdater.psd1        # Module manifest
  AvmUpdater.psm1        # Dot-sources Public/ and Private/
  Public/                # Exported functions
    Get-AvmModuleReference.ps1   # Scan files → AVM references
    Get-AvmLatestVersion.ps1     # Query registry → latest stable
    Get-AvmUpdatePlan.ps1        # Scan + lookup + risk → update candidates
    Get-AvmUpdateRisk.ps1        # Interface diff + changelog → risk tier
    New-AvmUpdateReport.ps1      # Plan → .md + .json report
    Approve-AvmUpdate.ps1        # Approval gate (local/github/azuredevops)
    Update-AvmModuleVersion.ps1  # Apply bumps + validate + rollback
    Invoke-AvmUpdate.ps1         # End-to-end orchestrator
  Private/               # Internal helpers (not exported)
    ConvertTo-SemVer.ps1         # Parse/sort semver tags
    Get-AvmUpdateType.ps1        # Classify patch/minor/major/none
    Invoke-WithRetry.ps1         # HTTP retry helper
    Get-AvmInterfaceDiff.ps1     # Interface comparison
    Get-AvmChangelog.ps1         # Changelog retrieval

config/
  avmupdater.config.json  # Defaults (risk tiers, globs, timeouts)

tests/
  fixtures/              # Sample .bicep and .tf files for tests
  *.Tests.ps1            # Pester 5 tests

.github/
  workflows/
    avm-update.yml       # GitHub Actions scheduled pipeline
azure-pipelines.avm-update.yml  # Azure DevOps scheduled pipeline
```

## Coding conventions

- **PowerShell 7+** with strict mode (`Set-StrictMode -Version Latest`).
- All public functions MUST have **comment-based help** with `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, and `.OUTPUTS`.
- Return **typed PSCustomObjects** (no raw hashtables from public functions).
- No `Write-Host` in library code; use `Write-Verbose` / `Write-Warning` / `Write-Error`.
- Configuration is always read from `avmupdater.config.json`; never hard-code defaults in function bodies.
- All network calls go through `Invoke-WithRetry` (timeout + retry from config).
- **Never crash the whole run** for one module's failure; surface it as `status='lookup-failed'` or `UNKNOWN`.
- Tests mock ALL external calls (`Invoke-RestMethod`, `bicep`, `terraform`, `git`, `gh`, `az`).

## Risk tiers

| Tier    | Meaning                                                                  |
|---------|--------------------------------------------------------------------------|
| LOW     | Patch bump, no interface change detected                                 |
| MEDIUM  | `0.x` minor bump, no breaking interface change detected                  |
| HIGH    | Major bump, OR breaking interface change, OR changelog mentions breaking |
| UNKNOWN | Diff unavailable AND changelog unavailable — gate as MEDIUM-or-higher    |

## Approval modes

| Mode          | How approval happens                                    |
|---------------|---------------------------------------------------------|
| local         | Interactive `Read-Host` prompts in terminal             |
| github        | Merge of the auto-generated PR is the approval          |
| azuredevops   | Merge of the auto-generated PR is the approval          |

## AVM module path conventions

- **Bicep MCR**: `br/public:avm/(res|ptn|utl)/<group>/<module>:<version>` or `br:mcr.microsoft.com/bicep/avm/(res|ptn|utl)/<group>/<module>:<version>`
- **Bicep tags API**: `GET https://mcr.microsoft.com/v2/bicep/avm/<category>/<group>/<module>/tags/list`
- **Terraform**: `source = "Azure/avm-(res|ptn|utl)-<name>/azurerm"` with `version = "..."`
- **Terraform API**: `GET https://registry.terraform.io/v1/modules/Azure/<avmModuleName>/azurerm/versions`
