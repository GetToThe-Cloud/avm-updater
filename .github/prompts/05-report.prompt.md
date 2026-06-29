---
mode: agent
description: Implement the Markdown overview + JSON manifest generator.
---
Follow `.github/copilot-instructions.md`. Depends on: `04-risk-analysis`.

Implement **`New-AvmUpdateReport`**. Input: the enriched plan from `Get-AvmUpdatePlan`.
Write both files to `-OutputDirectory` (default `./avm-report`):

1. **`avm-update-report.md`** — human overview:
   - Header: scan date, paths scanned, totals (modules scanned, updates found, counts by risk
     tier and by updateType).
   - Summary table: `Module | Ecosystem | Current | Latest | Jump | Risk | File:Line`.
   - Per-update detail for MEDIUM/HIGH: `riskReasons`, the interface diff (added/removed/
     changed inputs & outputs), changelog evidence lines.
   - Separate "Likely safe (LOW)" from "Needs review (MEDIUM/HIGH)", plus a dedicated
     "Could not check" section for `lookup-failed` / `UNKNOWN`.
2. **`avm-update-plan.json`** — the full machine-readable plan (the contract consumed by the
   updater).

**Rules:** group by file then risk (HIGH first), sort by risk then module name, render
cleanly in a GitHub / Azure DevOps PR description, pure function (no network calls).

**Acceptance**

- A sample plan (mixed LOW/MEDIUM/HIGH + one lookup-failed) produces both files; counts
  match; lookup-failed appears in "Could not check".
