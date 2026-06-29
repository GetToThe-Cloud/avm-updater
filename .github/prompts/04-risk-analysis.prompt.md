---
mode: agent
description: Implement breaking-change risk analysis (interface diff + changelog + semver).
---
Follow `.github/copilot-instructions.md`. Depends on: `03-version-lookup`.

Implement **`Get-AvmUpdateRisk`**, called by `Get-AvmUpdatePlan` to enrich each candidate.
This is the core "don't break the code" safeguard. Gather three independent signals:

**1) Version semantics** — major = breaking; `0.x` minor = potentially breaking;
patch = expected non-breaking.

**2) Interface diff (most important)** — compare the module's actual inputs/outputs between
current and target:

- bicep: prefer the compiled interface (param names, required vs has-default, types) by
  restoring each version and reading its `main.json`, or the MCR module metadata; fall back
  to fetching `main.bicep` at each version from `Azure/bicep-registry-modules`
  (`avm/<category>/<group>/<module>/main.bicep`) and diffing param/output declarations.
- terraform: fetch `variables.tf` + `outputs.tf` at both versions from the module's GitHub
  repo (`Azure/terraform-azurerm-<avmModuleName>`, tag = version) and diff variables (name,
  type, whether `default` exists) + outputs.
- **BREAKING:** required input added with no default; input removed/renamed; type changed;
  output removed/renamed. **NON-BREAKING:** new optional input; new output; description-only.

**3) Changelog / release notes (context, not authority)** — try `CHANGELOG.md` (Bicep: in
`bicep-registry-modules` under the module path; Terraform: GitHub Releases) between current
and target; extract lines mentioning breaking/removed/renamed (≤10). If unavailable, record
`changelog='unavailable'` — do NOT treat absence as safe.

**Risk tier** — HIGH (major, or breaking interface change, or changelog flags breaking);
MEDIUM (`0.x` minor, no detected breaking change); LOW (patch, no interface change);
UNKNOWN (diff couldn't be computed AND changelog unavailable → gate as MEDIUM-or-higher,
never silently LOW). Attach `riskTier`, `riskReasons[]` (each tied to concrete evidence: the
changed param name / changelog line / version-jump fact), and the raw interface diff.

**Acceptance**

- Mocked tests cover: removed required param (HIGH), added optional param (LOW/MEDIUM by
  bump), output removed (HIGH), patch with identical interface (LOW), diff-unavailable
  (UNKNOWN, not LOW). Every `riskReason` references concrete evidence.
