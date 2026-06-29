# AvmUpdater — CI/CD Setup Guide

This guide covers everything required to run **AvmUpdater** automatically in **GitHub Actions** and **Azure DevOps Pipelines**.

---

## Table of Contents

1. [How it works](#how-it-works)
2. [GitHub Actions setup](#github-actions-setup)
   - [Repository structure](#repository-structure-github)
   - [Required secrets](#required-secrets-github)
   - [Repository permissions](#repository-permissions-github)
   - [Enable the workflow](#enable-the-workflow)
   - [Manual trigger](#manual-trigger-github)
3. [Azure DevOps setup](#azure-devops-setup)
   - [Repository structure](#repository-structure-azure-devops)
   - [Required variables / secrets](#required-variables--secrets-azure-devops)
   - [Service connection permissions](#service-connection-permissions)
   - [Create the pipeline](#create-the-pipeline)
   - [Manual trigger](#manual-trigger-azure-devops)
4. [Approval flow](#approval-flow)
5. [Configuration reference](#configuration-reference)
6. [Troubleshooting](#troubleshooting)

---

## How it works

```
Schedule / Manual trigger
        │
        ▼
Invoke-AvmUpdate
  ├─ Scans all .bicep / .tf files for AVM module references
  ├─ Looks up latest stable version on MCR / Terraform Registry
  ├─ Classifies risk  (HIGH / MEDIUM / LOW / UNKNOWN)
  ├─ Generates report  (Markdown + JSON)
  ├─ Creates a branch, applies changes, opens a Pull Request
  └─ PR merge = approval gate  (never auto-merged)
```

The pipeline **never merges automatically**. A human must review and merge the PR.

---

## GitHub Actions setup

### Repository structure (GitHub)

The workflow file is already included in this repository:

```
your-infra-repo/
├── .github/
│   └── workflows/
│       └── avm-update.yml       ← the workflow
├── AvmUpdater/                  ← the PowerShell module (copy or submodule)
│   ├── AvmUpdater.psd1
│   ├── AvmUpdater.psm1
│   ├── Public/
│   └── Private/
└── config/
    └── avmupdater.config.json   ← optional, controls risk tiers and excludes
```

> **Tip:** Add AvmUpdater as a Git submodule so it can be updated independently:
> ```bash
> git submodule add https://github.com/GetToThe-Cloud/avm-updater AvmUpdater
> ```

---

### Required secrets (GitHub)

| Secret | Where to set | Description |
|--------|-------------|-------------|
| `GITHUB_TOKEN` | Automatic | Built-in. Already has `contents: write` and `pull-requests: write` if the workflow sets those permissions (it does). No action needed. |
| `GITHUB_TOKEN` with fine-grained PAT *(optional)* | `Settings → Secrets → Actions` | Only needed if your repository has branch protection rules that block the built-in token from pushing branches or creating PRs. Create a **fine-grained PAT** with `Contents: Read & Write` and `Pull requests: Read & Write`, then store it as `AVM_UPDATER_PAT`. Update the workflow `env:` block accordingly. |

**Set the built-in token permissions (required):**

1. Go to **Settings → Actions → General**
2. Under *Workflow permissions*, select **Read and write permissions**
3. Check **Allow GitHub Actions to create and approve pull requests**
4. Click **Save**

---

### Repository permissions (GitHub)

The workflow already declares:

```yaml
permissions:
  contents: write       # push branches
  pull-requests: write  # open PRs
```

This is applied at the job level and scopes the built-in `GITHUB_TOKEN` automatically.

---

### Enable the workflow

The workflow runs on a **weekly schedule (Mondays 08:00 UTC)** and can be triggered manually.

1. Copy `.github/workflows/avm-update.yml` to your infrastructure repository.
2. Copy the `AvmUpdater/` folder (or add as a submodule).
3. Push to `main` — the schedule activates automatically.

> GitHub only activates scheduled workflows on the **default branch**. If your default branch is not `main`, update the `branches` filter in the workflow.

---

### Manual trigger (GitHub)

1. Go to **Actions → AVM Module Version Check**
2. Click **Run workflow**
3. Optionally set:
   - **Risk tiers to include** (default: `LOW,MEDIUM,HIGH,UNKNOWN`)
   - **Dry run** — scans and generates report without opening a PR

---

## Azure DevOps setup

### Repository structure (Azure DevOps)

```
your-infra-repo/
├── azure-pipelines.avm-update.yml   ← the pipeline definition
├── AvmUpdater/                      ← the PowerShell module
│   ├── AvmUpdater.psd1
│   ├── AvmUpdater.psm1
│   ├── Public/
│   └── Private/
└── config/
    └── avmupdater.config.json
```

---

### Required variables / secrets (Azure DevOps)

| Variable | Type | Where to set | Description |
|----------|------|-------------|-------------|
| `System.AccessToken` | Built-in | Automatic | Used by the pipeline to authenticate git push and PR creation. Must be explicitly enabled (see below). |

**Enable `System.AccessToken`:**

1. Open your pipeline → **Edit**
2. Click the **⋮ menu → Triggers → YAML**
3. Or: go to **Project Settings → Pipelines → Settings**
4. Enable **Allow scripts to access the OAuth token**

Alternatively, add this to the pipeline YAML (already included):

```yaml
- job: avm_update
  pool:
    vmImage: ubuntu-latest
  variables:
    System.AccessToken: $(System.AccessToken)
```

**Branch policies and service account permissions:**

The pipeline agent pushes a branch and creates a PR using the **Project Collection Build Service** identity. Grant it:

1. Go to **Project Settings → Repositories → your-repo → Security**
2. Find `[ProjectName] Build Service (org-name)`
3. Grant:
   - **Contribute** → Allow
   - **Create branch** → Allow
   - **Create tag** → Allow (optional)

4. Go to **Project Settings → Repositories → your-repo → Policies**
5. Find **Pull request** settings and add the Build Service as a **bypass approver** *only if* branch policies would otherwise block the push (not recommended for production — prefer a dedicated service account).

---

### Create the pipeline

1. In Azure DevOps, go to **Pipelines → New pipeline**
2. Select **Azure Repos Git** (or GitHub if your repo is there)
3. Choose your repository
4. Select **Existing Azure Pipelines YAML file**
5. Set path to `/azure-pipelines.avm-update.yml`
6. Click **Continue → Save** (do not run yet)
7. Set the pipeline schedule: the YAML already includes a weekly cron — it activates automatically

---

### Manual trigger (Azure DevOps)

1. Go to **Pipelines → avm-update** (or your chosen name)
2. Click **Run pipeline**
3. Optionally set parameters:
   - **Risk tiers to include** (default: `LOW,MEDIUM,HIGH,UNKNOWN`)
   - **Dry run** — no file changes, no PRs

---

## Approval flow

Once the pipeline runs and finds updates, it:

1. Creates a branch: `avm-update/YYYYMMDD-HHmm`
2. Applies the version bumps to all approved files
3. Opens a Pull Request with:
   - The generated Markdown report as the PR body
   - All changed files in the diff

**To approve an update:** Review and merge the PR.  
**To reject an update:** Close the PR without merging. The next scheduled run will re-evaluate.

> The pipeline **never auto-merges**. The PR merge is the approval gate.

### Risk tier behaviour

| Tier | Default action | Notes |
|------|---------------|-------|
| `LOW` | Auto-included in PR | Patch bumps with no detected interface changes |
| `MEDIUM` | Auto-included in PR | Minor bumps on 0.x or no breaking signals |
| `HIGH` | Auto-included in PR | Major bumps or detected breaking changes |
| `UNKNOWN` | Auto-included in PR | Diff and changelog both unavailable |

All tiers are included in the PR by default. Review the PR diff and the attached report artifact before merging.

---

## Configuration reference

Place `config/avmupdater.config.json` in the root of your repository:

```json
{
  "autoApproveRiskTiers": ["LOW"],
  "manualApprovalRiskTiers": ["MEDIUM", "HIGH", "UNKNOWN"],
  "excludePaths": [
    "**/.terraform/**",
    "**/node_modules/**"
  ],
  "github": {
    "branchPrefix": "avm-update"
  },
  "azuredevops": {
    "branchPrefix": "avm-update"
  },
  "report": {
    "outputDirectory": "./avm-report"
  }
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `autoApproveRiskTiers` | `["LOW"]` | Risk tiers added to the PR without interactive prompt |
| `manualApprovalRiskTiers` | `["MEDIUM","HIGH","UNKNOWN"]` | Risk tiers that require human review in local mode |
| `excludePaths` | `[]` | Glob patterns excluded from scanning |
| `github.branchPrefix` | `avm-update` | Prefix for the created branch name |
| `azuredevops.branchPrefix` | `avm-update` | Prefix for the created branch name |
| `report.outputDirectory` | `./avm-report` | Where Markdown and JSON reports are written |

---

## Troubleshooting

### `az bicep` extension not found

```
WARNING: Azure CLI found but 'az bicep' extension is not installed.
```

Install it on the agent before running AvmUpdater:

```bash
az bicep install
```

Or use the standalone Bicep binary (already handled by the workflow):

```bash
curl -Lo bicep https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64
chmod +x bicep && sudo mv bicep /usr/local/bin/bicep
```

---

### Pipeline cannot push branch / create PR

**GitHub:** Ensure *Workflow permissions → Read and write* is enabled under **Settings → Actions → General**.

**Azure DevOps:** Grant **Contribute** and **Create branch** to the Build Service account on the repository (see [Service connection permissions](#service-connection-permissions)).

---

### Rate limits on GitHub API (interface diff / changelog)

AvmUpdater calls the GitHub API to fetch interface diffs and changelogs. Without authentication it is limited to 60 requests/hour.

Set a `GITHUB_TOKEN` (GitHub Actions) or a PAT stored as a pipeline secret to raise the limit to 5,000 requests/hour:

```yaml
# GitHub Actions — already present in the workflow
env:
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

```yaml
# Azure DevOps — add to the pwsh step
env:
  GITHUB_TOKEN: $(GITHUB_TOKEN)   # store as a pipeline secret variable
```

---

### Version lookup fails for a module

The module will appear in the **Could Not Check** section of the report. Common causes:

- MCR or Terraform Registry is temporarily unavailable
- The module path has changed (check the [AVM module index](https://azure.github.io/Azure-Verified-Modules/))
- The module has been deprecated

Add the module to `excludePaths` in `avmupdater.config.json` if you want to suppress repeated warnings.

---

### `Set-StrictMode` errors after upgrading AvmUpdater

Force-reload the module to clear any cached state:

```powershell
Import-Module ./AvmUpdater/AvmUpdater.psd1 -Force
```
