---
mode: agent
description: Implement registry version lookup and patch/minor/major classification.
---
Follow `.github/copilot-instructions.md`. Depends on: `02-scan`.

Implement **`Get-AvmLatestVersion`** (one module) and **`Get-AvmUpdatePlan`** (whole scan).

**`Get-AvmLatestVersion`** — fetch ALL available versions + the latest **stable**:

- bicep: `GET https://mcr.microsoft.com/v2/<registryPath>/tags/list` → use `tags`.
- terraform: `GET https://registry.terraform.io/v1/modules/<registryPath>/versions` → use
  `modules[0].versions[].version`.
- Drop non-semver / pre-release tags (`latest`, `*-preview`, `*-alpha`). Parse the rest with
  `[semver]`, sort descending, `latestStable` = highest.
- Cache responses in-memory for the run; timeout from config; retry with backoff (max 3); on
  failure mark `status='lookup-failed'` and continue (never crash the run for one module).

**`Get-AvmUpdatePlan`** — scan, look up each module, and emit "update candidates" with
`current`, `latestStable`, `updateType` (`none|patch|minor|major`), and a note that a `0.x`
minor jump is potentially breaking. Classification on `[semver]`: major differs → major;
major same & minor differs → minor; only patch differs → patch; equal → none. For Terraform
constraint refs, compute whether `latestStable` exceeds the constraint and flag a recommended
pin. Return only candidates with `updateType != none`, plus a summary count by `updateType`.

**Acceptance**

- Unit tests mock `Invoke-RestMethod` for both registries: correct `latestStable` (ignoring
  `latest`/preview tags) and correct `updateType` for patch/minor/major/equal.
- A `lookup-failed` module does not throw and is surfaced in the plan with its status.
