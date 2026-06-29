---
mode: agent
description: Implement Invoke-AvmUpdate — the single end-to-end pipeline entrypoint.
---
Follow `.github/copilot-instructions.md`. Depends on: `02`–`07`.

Implement **`Invoke-AvmUpdate`** — runs the whole pipeline.

**Params:** `-Path` (default `.`), `-Exclude <glob[]>`,
`-ApprovalMode <local|github|azuredevops>` (default `local`),
`-IncludeRisk <LOW|MEDIUM|HIGH|UNKNOWN>[]` (default all), `-DryRun`, `-OutputDirectory`,
`-ConfigPath`.

**Flow:**

1. `Get-AvmUpdatePlan` (scan + lookup + risk).
2. Filter by `-IncludeRisk`.
3. `New-AvmUpdateReport` — always, even on `-DryRun`, even with zero updates.
4. Zero updates ⇒ print "Everything is up to date" + report path, exit 0.
5. `Approve-AvmUpdate`.
6. local: `Update-AvmModuleVersion` on the approved subset with validation. github/azuredevops:
   the updater already ran inside approval to build the PR branch — surface its validation
   results in the PR body/output, don't double-apply.
7. Print a final summary (updated, skipped, rolled back, warnings, report path, PR URL).

**Rules:** idempotent (re-run when already current = no-op); clear plain-language summary;
exit codes 0 = success/no-op, non-zero if any update FAILED validation or a required CLI/token
is missing.

**Acceptance**

- `-DryRun` end-to-end: report + approval preview, zero file changes, zero pushes.
- local end-to-end on fixtures: applies an approved LOW update, validates, prints a correct
  summary.
