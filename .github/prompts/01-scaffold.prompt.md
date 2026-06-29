---
mode: agent
description: Scaffold the AvmUpdater PowerShell module skeleton with stubs and config.
---
Follow `.github/copilot-instructions.md`.

Scaffold the project. **Stubs + structure only** — no business logic yet.

Create:

- The module: `AvmUpdater/AvmUpdater.psd1` and `AvmUpdater.psm1` that dot-sources
  `/Public/*.ps1` and `/Private/*.ps1` and exports only the public functions.
- Stub public functions (each prints "not implemented yet" and returns `$null`):
  `Get-AvmModuleReference`, `Get-AvmLatestVersion`, `Get-AvmUpdatePlan`, `Get-AvmUpdateRisk`,
  `New-AvmUpdateReport`, `Approve-AvmUpdate`, `Update-AvmModuleVersion`, `Invoke-AvmUpdate`.
- `config/avmupdater.config.json` with defaults: `autoApproveRiskTiers` (`["LOW"]`),
  `manualApprovalRiskTiers` (`["MEDIUM","HIGH","UNKNOWN"]`), include/exclude path globs, and
  registry HTTP timeout/retry settings.
- A README stub describing the pipeline.
- Comment-based help on every public function.

**Acceptance**

- `Import-Module ./AvmUpdater` loads with no errors and all 8 stubs are callable.
- Each stub runs without throwing.
