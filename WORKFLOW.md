# Engineering Workflow

How we ship code across every `uspdan/*` project. Short, enforced, same in every repo.

## The short version

```
┌──────────────────────────────────────────────────────────────┐
│  branch off main  →  commit  →  push  →  PR  →  CI green    │
│                                                              │
│                →  squash-merge  →  staging auto-deploys      │
│                                                              │
│                →  release-please PR  →  merge  →  tag        │
│                                                              │
│                →  prod deploy (manual gate on tag)           │
└──────────────────────────────────────────────────────────────┘
```

No direct pushes to `main`. No merge commits. No manual version bumps. No manual CHANGELOG edits.

## Branch model — GitHub Flow

- `main` is always deployable. Direct pushes are blocked by branch protection.
- Feature branches are short-lived (target: same-day to 3-day lifetime):
  - `feat/<slug>` — new functionality
  - `fix/<slug>` — bug fix
  - `security/<slug>` — security patch (may fast-track review)
  - `chore/<slug>` — tooling / deps / internal
  - `docs/<slug>` — docs-only
- No `develop` branch. No release branches. No long-running feature branches (if it's >3 days, feature-flag it and merge increments).

## Commits — Conventional Commits

Every commit title matches `<type>(<scope>): <description>`. Enforced by `commitlint` on PR.

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `security`.

Examples:
- `feat(licence): add readonly interstitial on 402`
- `fix(kms): handle DER signatures with leading zero byte`
- `security(auth): rate-limit magic-link issue to 3/hour/email`

Breaking changes: add `!` after the type or include `BREAKING CHANGE:` in the body — both trigger a major version bump at release time.

## Pull requests

- PR must target `main`.
- PR title follows the same Conventional Commits format — it becomes the squash-merge commit title.
- PR description auto-populated from `.github/PULL_REQUEST_TEMPLATE.md`. Fill the checklist honestly.
- CI must be green before merge. Required status checks (enforced by branch protection):
  - `ci` — lint + typecheck + unit + e2e + browser + security scan
  - `sync-standards-check` — no drift from `engineering-standards`
  - `commitlint` — every commit title is valid Conventional Commits
- CODEOWNERS review required (solo-team: one self-review; that's not a rubber-stamp, use the PR template and review your own diff).
- Squash-merge only. The PR title becomes the commit on `main`. Feature-branch commit noise is lost by design.
- Branch auto-deleted after merge.

## Releases — release-please

After every merge to `main`, the `release-please` bot checks pending conventional commits. If there are any, it opens (or updates) a PR titled `chore(main): release X.Y.Z` that:
- bumps the version in `package.json` / `.release-please-manifest.json`
- writes a new section in `CHANGELOG.md` grouping changes by type
- when merged, creates a git tag `vX.Y.Z` and a GitHub Release

You don't edit `CHANGELOG.md` or tag manually. Merge the release PR → tag is created → prod deploy workflow fires.

### Version bumping

- `fix:` → patch (`X.Y.Z+1`)
- `feat:` → minor (`X.Y+1.0`)
- `feat!:` or body contains `BREAKING CHANGE:` → major (`X+1.0.0`)
- Pre-1.0: breaking changes bump minor instead of major.

## CI/CD

See each project's `.github/workflows/ci.yml` for specifics. Every project's pipeline has these stages in order:

```
install → lint → typecheck → unit → build → integration → security → package → deploy
```

- `install`: dependency resolution; fails if lockfile integrity broken.
- `lint`: zero-warnings policy (ESLint / ruff / clippy depending on language).
- `typecheck`: strict mode; no `any` / `# type: ignore`.
- `unit`: fast tests, no I/O.
- `build`: compile / bundle.
- `integration`: real-infra tests (test containers, in-memory DBs).
- `security`: `npm audit` (or `pip audit` / `cargo audit`); SAST if configured.
- `package`: build container; tag with `vX.Y.Z` + `sha-<short>`. Never tag `latest` in prod.
- `deploy`: staging auto-deploys on merge to `main`; prod requires manual approval on a tag.

## Standards-drift gate

Every project's CI includes a `sync-standards-check` job. It calls `engineering-standards/.github/workflows/reusable-sync-check.yml`, which:
1. Fetches `CLAUDE.md` / `CLAUDE.agent.md` / `LEARNINGS.md` from `engineering-standards@main`.
2. Diffs against the project's local copies.
3. Fails the job if any file drifts.

To resolve a drift failure: run `scripts/sync-standards.sh` in the project, commit the result, push. Never edit `CLAUDE.md` in a downstream repo — the change belongs in the `engineering-standards` repo and propagates from there.

## Pre-commit hooks (local fast feedback)

Every project installs `.husky/pre-commit` that runs:
- `lint-staged` on modified files (format + lint only what changed, fast)
- typecheck on the full tree (fast with incremental TS)

These are a convenience for local feedback. CI is the authoritative gate — `git commit --no-verify` can bypass locally but not on the PR.

## Branch protection (enforced on `main` in every repo)

- Require PR (no direct pushes).
- Require 1 approving review + CODEOWNERS review.
- Dismiss stale reviews on new commits.
- Require status checks: `ci`, `sync-standards-check`, `commitlint`, `release-please`.
- Require branch to be up-to-date with `main` before merge.
- Require linear history (squash-merge only, no merge commits).
- No force-push. No branch deletion.
- `enforce_admins: false` — repo admin (`@uspdan`) retains a break-glass override visible in the UI as a warning. Use it for emergencies only and document the reason in the incident doc.

## Incidents + break-glass

Genuine emergencies (prod down, active security incident) can bypass branch protection by pushing to `main` as admin. Every break-glass push must:
1. Be followed by a retroactive PR within 24 hours capturing the change + justification.
2. Be logged in the relevant project's incident-response runbook.
3. Be reviewed at the next post-incident review.

## Deprecating / removing standards

A change that invalidates in-flight work across projects (e.g., renaming a core utility, deleting a required pattern) is a **breaking change** at the standards level:
- Mark with `feat!:` or `BREAKING CHANGE:` in the commit.
- Major version bump via release-please.
- Downstream repos must re-sync explicitly; they pick up the new standards when their `sync-standards.sh` runs.
- Plan the cutover across projects before merging the breaking change — not after.
