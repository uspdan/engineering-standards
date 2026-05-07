---
description: Run the full secure-build pipeline (Architect → Builder → Defender → Reviewers → Red-team → Compliance → Codex) on a feature/change request, with written artifacts at every handoff.
allowed-tools: Read, Grep, Glob, Bash, Write, Agent, AskUserQuestion
---

# /secure-build

You are about to drive a coordinated team of specialist subagents through a deterministic pipeline that produces high-integrity, low-vulnerability code on this project.

**Task:** $ARGUMENTS

If $ARGUMENTS is empty, ask the user (via AskUserQuestion) what feature or change to run through the pipeline before proceeding.

## Your job (as the invoking session)

You are the orchestrator's launch shell, not the orchestrator itself. Your job is to:

1. Verify the project context:
   - The working directory must be inside a project (presence of any of: `.git/`, `package.json`, `pyproject.toml`, `Cargo.toml`, `CLAUDE.md`).
   - `~/.claude/refs/CLAUDE.md` must exist (synced engineering standards).
   - `~/.claude/scripts/codex-preflight.sh` and `~/.claude/scripts/reuse-inventory.sh` must exist and be executable.
   - `codex` must be on PATH.
   - If any of these is missing, stop and tell the user how to fix (`./scripts/install-secure-build.sh` from `engineering-standards/`, `codex login`, etc.).

2. Hand off to the orchestrator subagent via the `Agent` tool, type `orchestrator`, with a prompt that contains:
   - The user's task ($ARGUMENTS).
   - The project root path.
   - A pointer to `~/.claude/refs/roles/orchestrator.md` for the full process.

3. After the orchestrator returns, read `<run>/summary.md` and report to the user:
   - The run directory path.
   - The verdict (APPROVED / KICKED-BACK / BLOCKED-AT-DESIGN / PAUSED-FOR-LEGAL).
   - The list of artifacts produced.
   - Any residual risks accepted (so the user can audit).

## Pipeline summary (so the user knows what's happening)

```
1. INTAKE       — restate task, identify trust boundaries / regulated data
2. INVENTORY    — find existing utils to reuse before writing new code
3. ARCHITECT    — threat-model.md (gate: must approve before build)
4. BUILD        — implement against architect's contract; tests in-line
5. HARDEN       — defensive guards, allow-lists, fail-closed, timeouts, redaction
6. INTERNAL QA  — code-reviewer + appsec-reviewer + qa-engineer in parallel
7. RED TEAM     — runnable PoCs against threat-model controls (local scope only)
8. COMPLIANCE   — privacy/regulatory review when PII/audit applicable
9. CODEX        — OpenAI Codex review as external validator; loop until clean (cap 3)
10. SIGN-OFF    — summary.md with verdict + artifact index
```

Artifacts land under `<project>/.claude/runs/<UTC-timestamp>-<slug>/`.

## What you do NOT do

- You do not implement, threat-model, review, exploit, or test yourself.
- You do not skip the orchestrator. Even for trivial-seeming tasks, run the pipeline.
- You do not auto-commit. The user inspects the run dir and the working tree, then commits.
