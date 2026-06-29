---
mode: agent
description: Add Pester tests, mocks, PSScriptAnalyzer compliance, and full docs.
---
Follow `.github/copilot-instructions.md`. Depends on: `02`–`09`.

Harden and document **AvmUpdater**.

**Tests (Pester 5):**

- Unit-test every public + key private function with `Invoke-RestMethod` and external CLIs
  (`bicep`/`terraform`/`git`/`gh`/`az`) **mocked** — no real network or repo calls in unit
  tests.
- Cover the matrix: bicep & terraform; patch/minor/major/none; interface diffs (breaking vs
  non-breaking); risk tiers incl. UNKNOWN; lookup-failed modules; approval modes (local
  approve/skip, PR creation mocked); updater PASS/WARN/FAIL with rollback; `-DryRun` changes
  nothing.
- Add an opt-in integration test (behind an env flag) against `/tests/fixtures` using real
  `bicep`/`terraform` CLIs when present.

**Quality:**

- PSScriptAnalyzer-clean; comment-based help with examples on all public functions.
- A README covering prerequisites, install, the `avmupdater.config.json` options (esp.
  auto-approve vs manual-approval risk tiers), the three approval modes, the three exit codes,
  and a "how the safety/validation works" section.
- A `CHANGELOG.md` for the tool itself.

**Acceptance**

- `Invoke-Pester` passes; PSScriptAnalyzer reports no errors.
- The README lets a new engineer run it locally and understand the PR-based CI flow.
