# engineering-standards

Canonical engineering standards + workflow for every project under `uspdan/*`.
Downstream repos sync the files here into their own root so every Claude
Code instance, CI run, and human contributor follows the same rules.

## What's in this repo

| File | What it is |
|---|---|
| `CLAUDE.md` | The engineering playbook — architecture rules, testing standards, security controls, git workflow, CI/CD requirements. Synced verbatim to every project. |
| `CLAUDE.agent.md` | The always-on Claude Code agent that enforces `CLAUDE.md`, captures learnings, and promotes cross-project patterns. |
| `LEARNINGS.md` | Cross-project lessons promoted from individual `CLAUDE.memory.md` files (promotion criteria: seen in ≥2 projects, or severe enough that one occurrence is universal). |
| `WORKFLOW.md` | The engineering workflow itself — branch model, PR flow, release process, how to propose a standards change. |
| `scripts/sync-standards.sh` | Pulls the three files above from this repo into a downstream project. Runs locally OR in CI (`--check` mode fails the build on drift). |
| `scripts/bootstrap-standards.sh` | One-shot project scaffolder. Drops in `.github/*`, release tooling, pre-commit hooks, CHANGELOG skeleton. Idempotent. |

## How downstream repos consume this

Every project under `uspdan/*` has `.github/workflows/sync-standards-check.yml`
that calls this repo's `reusable-sync-check.yml` workflow on every PR. If
a project's local copy of `CLAUDE.md` drifts from this repo's copy, the
project's CI goes red until the project re-syncs.

Run `scripts/sync-standards.sh` from inside a downstream project to refresh.

## Proposing a change to the standards

1. Branch off `main`: `git checkout -b feat/<short-description>`.
2. Edit `CLAUDE.md` (or whichever file).
3. Open a PR. The `validate` workflow lints markdown + checks links. CODEOWNERS review required.
4. On merge, `release-please` opens a release PR with a new version bump + CHANGELOG entry.
5. Merge the release PR. All downstream project CIs now fail the drift check until they re-sync.

Drift failure is the feature, not a bug — it forces every project to deliberately adopt standards changes.

## Setting up a new project

```bash
cd /path/to/your-new-project
bash <(curl -fsSL https://raw.githubusercontent.com/uspdan/engineering-standards/main/scripts/bootstrap-standards.sh)
```

Scaffolds everything you need to match the `uspdan/*` engineering workflow.

## Repo structure

```
.github/
  CODEOWNERS                       — every PR auto-requests @uspdan
  PULL_REQUEST_TEMPLATE.md         — Appendix-A compliance checklist
  dependabot.yml                   — weekly dep scans
  workflows/
    validate.yml                   — markdownlint + link-check on PR
    reusable-sync-check.yml        — called by downstream repos on every PR
    release-please.yml             — auto-tag + CHANGELOG on merged conv. commits
scripts/
  sync-standards.sh                — local OR remote sync + --check mode
  bootstrap-standards.sh           — scaffold a new project
CLAUDE.md
CLAUDE.agent.md
LEARNINGS.md
WORKFLOW.md
CHANGELOG.md
commitlint.config.cjs
release-please-config.json
.release-please-manifest.json
```

## Versioning

Follows SemVer. `release-please` bumps:
- **patch**: `fix:` commits (typo, small clarification)
- **minor**: `feat:` commits (new section, new rule)
- **major**: breaking changes (a rule that invalidates in-flight work across projects)

Downstream repos can pin to a specific tag (`scripts/sync-standards.sh --ref v1.2.3`) or track `main` (default).
