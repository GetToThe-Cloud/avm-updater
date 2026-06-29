---
mode: agent
description: Implement the approval gate — local, GitHub PR, and Azure DevOps PR modes.
---
Follow `.github/copilot-instructions.md`. Depends on: `05-report`, `07-updater`.

Implement **`Approve-AvmUpdate`**. Input: the plan + the report path. Param
`-ApprovalMode <local|github|azuredevops>`. Output: the **approved** subset + an audit record
(mode, timestamp, approvedItems[], skippedItems[], actor). Policy from config:
`autoApproveRiskTiers` proceed without sign-off; everything else needs a human.

**local (interactive):** print the color-coded summary table; for each manual-approval update
prompt approve/skip (support "approve all LOW", "review each", "skip all") via `Read-Host`;
honor `-DryRun` (show what would be asked, change nothing).

**github (PR = approval):** require `GITHUB_TOKEN`; detect `gh` (fall back to REST API).
Create a branch `avm-updates/<yyyyMMdd-HHmm>`, apply the updates (call the updater), commit,
push, open a PR whose body is the Markdown report, label by highest risk (`avm-update`,
`risk:high`). **Never auto-merge** — the PR review/merge is the approval. Return the PR URL.
Optionally split LOW vs MEDIUM/HIGH into two PRs so safe bumps merge fast.

**azuredevops (PR = approval):** require `SYSTEM_ACCESSTOKEN` / `AZURE_DEVOPS_EXT_PAT`; detect
`az` + the azure-devops extension. Same flow via `az repos pr create`; branch policies /
required reviewers enforce approval. Return the PR URL.

**Rules:** never apply MEDIUM/HIGH/UNKNOWN without an explicit human gate in the active mode;
all three modes return the same shape so the orchestrator stays mode-agnostic.

**Acceptance**

- local: scripted input approves LOW + one MEDIUM, skips a HIGH → correct subset + audit.
- github/azuredevops (CLI mocked): branch + commit + PR created with the report as the body
  and correct risk labels; nothing auto-merged.
