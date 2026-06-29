# AVM Updater 

### Prerequisites

| Tool | Purpose |
|------|---------|
| PowerShell 7+ | Module runtime |
| [Bicep CLI](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install) or `az` with Bicep | Validation of Bicep files |
| [Terraform CLI](https://developer.hashicorp.com/terraform/install) | Validation of Terraform files |
| `git` | Branch management for PR modes |
| `gh` (GitHub CLI) | GitHub PR creation (github mode) |
| `az` + azure-devops extension | Azure DevOps PR creation (azuredevops mode) |

Tokens for `github` mode: `GITHUB_TOKEN` env variable.
Tokens for `azuredevops` mode: `SYSTEM_ACCESSTOKEN` or `AZURE_DEVOPS_EXT_PAT` env variable.

### Install

```powershell
Import-Module ./AvmUpdater/AvmUpdater.psd1
```

Or add the `AvmUpdater/` folder to a `$env:PSModulePath` location and use:

```powershell
Import-Module AvmUpdater
```

### Quick start — local interactive

```powershell
Import-Module ./AvmUpdater/AvmUpdater.psd1

# Scan ./infra, review updates interactively, apply approved ones
Invoke-AvmUpdate -Path ./infra -ApprovalMode local
```

### Dry run (no changes, no PRs)

```powershell
Invoke-AvmUpdate -Path . -DryRun
```

### GitHub PR-based approval

```powershell
$env:GITHUB_TOKEN = 'ghp_...'
Invoke-AvmUpdate -Path . -ApprovalMode github -IncludeRisk @('LOW','MEDIUM','HIGH')
```

### Azure DevOps PR-based approval

```powershell
$env:SYSTEM_ACCESSTOKEN = '...'
Invoke-AvmUpdate -Path . -ApprovalMode azuredevops
```

### Configuration — `config/avmupdater.config.json`

| Key | Default | Description |
|-----|---------|-------------|
| `autoApproveRiskTiers` | `["LOW"]` | Tiers approved without sign-off |
| `manualApprovalRiskTiers` | `["MEDIUM","HIGH","UNKNOWN"]` | Tiers that require a human gate |
| `includePaths` | `["**/*.bicep","**/*.tf"]` | Glob patterns for files to scan |
| `excludePaths` | `.terraform/**`, `node_modules/**`, … | Glob patterns to skip |
| `registry.httpTimeoutSeconds` | `30` | Per-request HTTP timeout |
| `registry.maxRetries` | `3` | Max retries on transient failures |
| `registry.retryDelaySeconds` | `2` | Base delay (doubles each retry) |
| `report.outputDirectory` | `./avm-report` | Where report files are written |
| `github.branchPrefix` | `avm-updates` | Branch name prefix for PR modes |
| `github.splitLowFromHigherRisk` | `false` | Open separate PRs for LOW vs MEDIUM+ |

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success (updates applied or already up to date) |
| `1` | One or more updates failed validation and were rolled back, or a required CLI/token is missing |

### How safety/validation works (3 layers)

1. **Version semantics** — AVM is `0.x`, so a *minor* bump is treated as potentially breaking
   (`MEDIUM` risk). A *major* bump is always `HIGH`. A *patch* bump starts as `LOW`.

2. **Interface diff** — for Bicep, the module's `main.bicep` is fetched at both versions from
   the `Azure/bicep-registry-modules` GitHub repo and param/output declarations are diffed.
   For Terraform, `variables.tf` + `outputs.tf` are compared. Any BREAKING change (required
   input added, input removed/renamed, type changed, output removed) raises the tier to `HIGH`.

3. **Validate before accepting** — after editing a file, `bicep build`/`lint` or
   `terraform init`/`validate`/`plan` is run. If validation fails, **that one file is reverted
   to its original bytes** (other files are not affected). A Terraform plan that includes
   DESTROY or REPLACE actions is flagged as `WARN` (kept, but highlighted for review).

### How the PR-based CI flow works

1. The scheduled pipeline runs `Invoke-AvmUpdate -ApprovalMode github` (or `azuredevops`).
2. The tool scans, analyses risk, generates a report, creates a branch, applies updates,
   validates them, commits, and opens a PR whose body is the Markdown report.
3. A human reviews the PR. **Merging the PR is the approval.**
4. For MEDIUM/HIGH updates, configure branch protection (required reviewers) to enforce review.

### Running the tests

```powershell
# Install Pester 5 if needed
Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force

# Run all tests
Invoke-Pester ./tests/AvmUpdater.Tests.ps1 -Output Detailed
```

### PSScriptAnalyzer

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path ./AvmUpdater -Recurse
```

---

## How approval works (all three modes)

- **local** — interactive y/n in the terminal; safe (LOW) bumps can auto-approve, risky ones
  prompt per item.
- **github** — the tool bumps versions on a branch, validates, and opens a **Pull Request**
  with the overview as the description. **Merging the PR is the approval.**
- **azuredevops** — same flow via `az repos pr create`; **branch policies / required
  reviewers** enforce approval.

## How breakage is prevented (3 layers)

1. **Version semantics** — AVM is `0.x`, so a *minor* bump is treated as potentially breaking.
2. **Interface diff** — an added required input, a removed/renamed parameter or output, or a
   type change between versions is flagged BREAKING.
3. **Validate before accepting** — `bicep build`/`lint` and `terraform init/validate/plan`
   (with destroy/replace detection); any failure is rolled back per file. Code that does not
   validate is never reported as a success.

## Prerequisites for the built tool

PowerShell 7+, the Bicep CLI (or `az` with Bicep), the Terraform CLI, `git`, and — for the PR
modes — `gh` (GitHub) or the `az` CLI + `azure-devops` extension. Tokens are read from
environment variables only.
