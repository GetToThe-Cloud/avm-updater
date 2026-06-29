---
mode: agent
description: Implement the safe updater — apply bumps, validate, roll back on failure.
---
Follow `.github/copilot-instructions.md`. Depends on: `05-report`.

Implement **`Update-AvmModuleVersion`**. Input: the **approved** plan. Make the edits and
prove the code still builds/plans — rolling back anything that fails.

**Edit** — rewrite ONLY the version token at the recorded `file:line`:
`...:<old>` → `...:<new>` (bicep) / `version = "<old>"` → `version = "<new>"` (terraform),
preserving all surrounding formatting/quoting. Keep a backup of each original file for a
precise rollback. Never reformat surrounding code.

**Validate** (must pass before an update counts as good):

- bicep: `bicep build` (or `az bicep build`) + `bicep lint` on each touched file/entrypoint;
  surface restore failures clearly.
- terraform: in each touched directory run `terraform init -upgrade`, `terraform validate`,
  `terraform plan -detailed-exitcode -no-color` (0=no change, 2=changes, 1=error). Parse the
  plan for DESTROY/REPLACE actions + resource count deltas — a replace/destroy is a
  breaking-behaviour signal even if it "validates".

**Outcome per update:** PASS (builds/validates, no destroy/replace) · WARN (validates but the
plan replaces/destroys or shows a large diff → keep, flag for attention) · FAIL
(build/validate/init error → roll back **that one file**, keep the rest, capture the error
output).

**Rules:** updates are independent (one failure doesn't block others); respect `-DryRun`
(edit a temp copy, validate, never persist/push); return `applied[]`, `rolledBack[]`
(+errors), `warnings[]`, and a "tree is consistent" assertion; exit non-zero if any FAIL.
Never report success for a file that didn't validate.

**Acceptance**

- CLIs mocked: a clean patch → PASS + version changed; a build-failing update → that file
  reverted to its original bytes, others still applied, error captured; a terraform plan with
  a replace → WARN, change kept, flagged.
