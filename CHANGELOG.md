
# Changelog — AvmUpdater

All notable changes to **AvmUpdater** will be documented in this file.
This project adheres to [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

## [1.0.0] — 2026-06-29

### Changed

- Promoted to stable 1.0.0 release.

## [0.1.0] — 2026-06-29

### Added

- Initial release of AvmUpdater PowerShell module.
- **`Get-AvmModuleReference`** — recursively scans Bicep (`.bicep`) and Terraform (`.tf`)
  files for AVM module references; handles both `br/public:` short-hand and full MCR paths,
  plus Terraform `source =` + `version =` blocks. Supports constraint refs (`~>`).
- **`Get-AvmLatestVersion`** — queries MCR tags API (Bicep) or Terraform Registry versions API;
  filters out pre-release/preview tags; in-memory cache per run; retries with exponential
  back-off; never crashes on a single module failure.
- **`Get-AvmUpdatePlan`** — combines scan + version lookup + risk analysis into a single plan
  object with summary counts by updateType and risk tier.
- **`Get-AvmUpdateRisk`** — three-signal risk classifier: version semantics, interface diff
  (params/outputs via GitHub raw source), changelog evidence. Returns HIGH / MEDIUM / LOW /
  UNKNOWN with concrete `riskReasons[]`.
- **`New-AvmUpdateReport`** — writes `avm-update-report.md` (human overview) and
  `avm-update-plan.json` (machine-readable) to a configurable output directory. Pure function.
- **`Approve-AvmUpdate`** — three approval modes:
  - `local`: interactive `Read-Host` with bulk approve / skip / review-each options.
  - `github`: auto-generates a PR; merge = approval. Never auto-merges.
  - `azuredevops`: same via `az repos pr create`.
- **`Update-AvmModuleVersion`** — rewrites only the version token at the recorded file:line;
  validates with `bicep build`/`lint` or `terraform init`/`validate`/`plan`; per-file rollback
  on failure; DESTROY/REPLACE detection flagged as WARN.
- **`Invoke-AvmUpdate`** — end-to-end orchestrator with `-DryRun`, `-IncludeRisk` filter,
  idempotent no-op when up to date, final summary with exit codes.
- `config/avmupdater.config.json` — configurable risk tiers, path globs, HTTP timeouts.
- GitHub Actions workflow (`.github/workflows/avm-update.yml`) — weekly schedule +
  `workflow_dispatch`; uploads report artifact.
- Azure DevOps pipeline (`azure-pipelines.avm-update.yml`) — weekly schedule + parameters;
  publishes report artifact.
- Pester 5 test suite (`tests/AvmUpdater.Tests.ps1`) — all external calls mocked; covers
  scanner, version lookup, risk tiers, report generation, approval modes, updater
  PASS/WARN/FAIL, rollback, and DryRun end-to-end.
- Fixture files (`tests/fixtures/sample.bicep`, `tests/fixtures/sample.tf`).
