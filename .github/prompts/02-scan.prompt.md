---
mode: agent
description: Implement the AVM scanner — find module references and current versions.
---
Follow `.github/copilot-instructions.md`. Depends on: `01-scaffold`.

Implement **`Get-AvmModuleReference`**: recursively scan a directory for AVM references in
Bicep and Terraform and return normalized objects.

**Input:** `-Path <dir>` (default `.`), `-Exclude <glob[]>` (e.g. `**/.terraform/**`).

**Bicep** (`*.bicep`) — match both forms:
`'br/public:avm/(res|ptn|utl)/<group>/<module>:<version>'` and
`'br:mcr.microsoft.com/bicep/avm/(res|ptn|utl)/<group>/<module>:<version>'`.
Capture: `ecosystem='bicep'`, category, group, module, currentVersion,
`registryPath` (the MCR tags path, e.g. `bicep/avm/res/<group>/<module>`), file, lineNumber,
rawMatch.

**Terraform** (`*.tf`) — an AVM `module "x" { ... }` block with
`source = "Azure/avm-(res|ptn|utl)-<name>/azurerm"` and `version = "..."` (lines in any
order). Capture: `ecosystem='terraform'`, avmModuleName, currentVersion (if a constraint like
`~> 0.1`, set `isConstraint=$true` + the raw constraint), `registryPath`
(`Azure/<avmModuleName>/azurerm`), file, lineNumber, rawMatch.

**Rules:** resilient to whitespace / single & double quotes / inline comments; dedupe
identical tuples; return typed objects (no host output); ignore non-AVM modules entirely.

**Acceptance**

- Add `/tests/fixtures`: a `.bicep` file with two `res` modules + one `ptn` module (mixed ref
  forms) and a `.tf` file with two `res` modules (one pinned, one `~>` constraint).
  `Get-AvmModuleReference` returns exactly the expected objects.
- A constraint (not a pin) is flagged `isConstraint=$true`.
