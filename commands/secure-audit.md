---
description: Run a project-wide security audit (Architect → Reviewers → Red-team → Blue-team → Compliance → Codex) against the entire working tree, producing a written audit report with prioritised findings.
allowed-tools: Read, Grep, Glob, Bash, Write, Agent, AskUserQuestion
---

# /secure-audit

You are about to drive a coordinated team of specialist subagents through a project-wide audit. Unlike `/secure-build`, there is no diff and no implementation phase — the deliverable is a risk register and prioritised fix list covering the entire codebase as it stands.

**Audit scope (optional):** $ARGUMENTS

If `$ARGUMENTS` is empty, the orchestrator will treat the whole working tree as in-scope and infer exclusions from `.gitignore`. If the user supplied a sub-path, glob, or focus area (e.g. `src/api/`, `auth and billing only`), pass it through.

## Your job (as the invoking session)

You are the orchestrator's launch shell, not the orchestrator itself. Your job is to:

1. Verify the project context:
   - The working directory must be inside a project (presence of any of: `.git/`, `package.json`, `pyproject.toml`, `Cargo.toml`, `CLAUDE.md`).
   - `~/.claude/refs/CLAUDE.md` must exist (synced engineering standards).
   - `~/.claude/refs/roles/orchestrator-audit.md` must exist.
   - `~/.claude/scripts/codex-preflight.sh` must exist and be executable.
   - `codex` must be on PATH.
   - If any of these is missing, stop and tell the user how to fix.

2. Hand off to the orchestrator subagent via the `Agent` tool, type `orchestrator`, with a prompt that contains:
   - Mode: `AUDIT` (project-wide; no diff, no build phase).
   - The user's scope hint (`$ARGUMENTS`) if any.
   - The project root path.
   - An instruction to follow `~/.claude/refs/roles/orchestrator-audit.md` (not `orchestrator.md`) for the full process.

3. After the orchestrator returns, read `<run>/audit-report.md` and report to the user:
   - The run directory path.
   - The verdict (CLEAR / FINDINGS / BLOCKED-AT-DESIGN / PAUSED-FOR-LEGAL).
   - Counts by severity (Critical / High / Medium / Low).
   - The top-3 prioritised fixes.
   - Any residual risks the orchestrator flagged for explicit acceptance.

## Pipeline summary (so the user knows what's happening)

```
1. INTAKE       — capture scope, sensitivity hints, regulated-data flags
2. INVENTORY    — enumerate languages, entrypoints, infra surfaces, dependencies
3. ARCHITECT    — project-wide threat-model.md: asset & boundary catalog, top threats
4. REVIEWS      — code-reviewer + appsec-reviewer + qa-engineer in parallel, whole tree
5. RED TEAM     — runnable PoCs against Medium+ threats on a live local instance
6. BLUE TEAM    — verify each red-team attack would be detectable; audit log/alert coverage
7. COMPLIANCE   — privacy/regulatory review (run unless intake confirms no regulated data)
8. CODEX        — external validator pass over the findings; loop until clean (cap 3)
9. REPORT       — audit-report.md with risk register + prioritised fixes
```

Artifacts land under `<project>/.claude/runs/<UTC-timestamp>-audit-<slug>/`.

## What you do NOT do

- You do not implement, threat-model, review, exploit, or test yourself.
- You do not modify source files. An audit is read-only by design — fixes happen in follow-up `/secure-build` runs.
- You do not skip the orchestrator. Even for small projects, run the pipeline.
- You do not auto-commit. The audit report is for the user to review and triage.
