#!/usr/bin/env bash
# scripts/bootstrap-standards.sh
#
# One-shot scaffolder. Run once when setting up a new uspdan/* project or
# retrofitting an existing one. Idempotent — skips anything already in place.
#
# Drops in:
#   - CLAUDE.md / CLAUDE.agent.md / LEARNINGS.md (synced from engineering-standards)
#   - CLAUDE.memory.md skeleton
#   - .gitignore additions for memory backups + env
#   - scripts/sync-standards.sh (latest version, fetched from engineering-standards)
#   - docs/adr/000-template.md
#   - .github/CODEOWNERS, PULL_REQUEST_TEMPLATE.md, dependabot.yml
#   - .github/workflows/sync-standards-check.yml (drift guard in CI)
#   - .github/workflows/release-please.yml + config
#   - commitlint.config.cjs
#   - .husky/pre-commit + lint-staged wiring
#   - CHANGELOG.md skeleton
#
# Usage:
#   ./scripts/bootstrap-standards.sh              # remote sync from engineering-standards
#   ./scripts/bootstrap-standards.sh /path        # local path for offline / test

set -euo pipefail

PROJECT_ROOT="$(cd "$(pwd)" && pwd)"
STANDARDS_SOURCE="${1:-}"
REMOTE_BASE="https://raw.githubusercontent.com/uspdan/engineering-standards/main"
DATE=$(date +%Y-%m-%d)

echo "=== Engineering Standards Bootstrap ==="
echo "Project root: ${PROJECT_ROOT}"
echo ""

# ── Helpers ──────────────────────────────────────────────────────────
create_if_missing() {
  local filepath="$1"
  local description="$2"
  if [[ -f "${filepath}" ]]; then
    echo "[SKIP] ${filepath} already exists"
    return 1
  fi
  echo "[CREATE] ${filepath} — ${description}"
  mkdir -p "$(dirname "${filepath}")"
  return 0
}

fetch_from_source() {
  # $1 = path inside engineering-standards repo (e.g., "CLAUDE.md" or "scripts/sync-standards.sh")
  # $2 = destination path on disk
  # Priority: local path → gh api (handles private repos) → curl (public only)
  local name="$1" target="$2"
  if [[ -n "${STANDARDS_SOURCE}" && -f "${STANDARDS_SOURCE}/${name}" ]]; then
    cp "${STANDARDS_SOURCE}/${name}" "${target}"
    return 0
  fi
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if gh api "repos/uspdan/engineering-standards/contents/${name}" \
        -H 'Accept: application/vnd.github.raw' > "${target}" 2>/dev/null; then
      return 0
    fi
  fi
  curl -fsSL --max-time 15 -o "${target}" "${REMOTE_BASE}/${name}"
}

append_unique() {
  local file="$1" line="$2"
  touch "${file}"
  grep -qxF "${line}" "${file}" 2>/dev/null || echo "${line}" >> "${file}"
}

# ── 1. Directory structure ───────────────────────────────────────────
echo "--- Setting up directories ---"
mkdir -p "${PROJECT_ROOT}"/{.memory-backups,docs/adr,docs/runbooks,docs/memory-archive,scripts,.github/workflows,.husky}

# ── 2. .gitignore additions ──────────────────────────────────────────
echo "--- Updating .gitignore ---"
GITIGNORE="${PROJECT_ROOT}/.gitignore"
touch "${GITIGNORE}"
for entry in ".memory-backups/" ".env" ".env.local" ".env.*.local" ".husky/_" "node_modules/"; do
  append_unique "${GITIGNORE}" "${entry}" && echo "[OK] ${entry}"
done

# ── 3. Synced standards files (canonical from engineering-standards) ──
echo "--- Syncing standards files ---"
for f in CLAUDE.md CLAUDE.agent.md LEARNINGS.md; do
  tmp="$(mktemp)"
  if fetch_from_source "${f}" "${tmp}"; then
    mv "${tmp}" "${PROJECT_ROOT}/${f}"
    echo "[SYNC] ${f}"
  else
    rm -f "${tmp}"
    echo "[WARN] ${f} could not be synced — create manually or re-run with network"
  fi
done

# ── 4. CLAUDE.memory.md skeleton ─────────────────────────────────────
if create_if_missing "${PROJECT_ROOT}/CLAUDE.memory.md" "Project memory"; then
  cat > "${PROJECT_ROOT}/CLAUDE.memory.md" << MEMORY_EOF
# CLAUDE.memory.md — Project Memory: $(basename "${PROJECT_ROOT}")

> Project-specific learnings, patterns, gotchas, and decisions.
> Claude Code reads this automatically. Entries are append-only.
>
> **Initialized**: ${DATE}

---

## PATTERNS — What works in this project

_No entries yet._

---

## GOTCHAS — What has bitten us

_No entries yet._

---

## DECISIONS — Why we chose X over Y

_No entries yet._

---

## DEBT — Known shortcuts and their remediation plan

_No entries yet._

---

## PERFORMANCE — Benchmarks and capacity observations

_No entries yet._

---

## DEPENDENCIES — External dependency notes

_No entries yet._

---

## ENVIRONMENT — Infrastructure and deployment notes

_No entries yet._

---

## ROLLBACK LOG — What we rolled back and why

_No entries yet._
MEMORY_EOF
fi

# ── 5. Sync script (always refreshed to canonical version) ───────────
echo "--- Installing sync-standards.sh ---"
if fetch_from_source "scripts/sync-standards.sh" "${PROJECT_ROOT}/scripts/sync-standards.sh"; then
  chmod +x "${PROJECT_ROOT}/scripts/sync-standards.sh"
  echo "[SYNC] scripts/sync-standards.sh (latest)"
else
  echo "[WARN] could not fetch sync-standards.sh — run manually"
fi

# ── 6. ADR template ──────────────────────────────────────────────────
if create_if_missing "${PROJECT_ROOT}/docs/adr/000-template.md" "ADR template"; then
  cat > "${PROJECT_ROOT}/docs/adr/000-template.md" << 'ADR_EOF'
# ADR-NNN: Title

## Status
Proposed | Accepted | Superseded by ADR-NNN

## Context
What is the issue that we're seeing that is motivating this decision?

## Decision
What is the change that we're proposing and/or doing?

## Consequences
What becomes easier or more difficult to do because of this change?

## References
- Related MEM entries: MEM-NNNN
- Related PRs: #NN
ADR_EOF
fi

# ── 7. .github metadata ──────────────────────────────────────────────
echo "--- Installing .github metadata ---"

if create_if_missing "${PROJECT_ROOT}/.github/CODEOWNERS" "code owners"; then
  echo '* @uspdan' > "${PROJECT_ROOT}/.github/CODEOWNERS"
fi

if create_if_missing "${PROJECT_ROOT}/.github/PULL_REQUEST_TEMPLATE.md" "PR template"; then
  cat > "${PROJECT_ROOT}/.github/PULL_REQUEST_TEMPLATE.md" << 'PRT_EOF'
## Summary

<!-- What changed and why. Two to four sentences. -->

## Scope

- [ ] Docs only
- [ ] Infra / tooling
- [ ] New feature
- [ ] Bug fix
- [ ] Security patch
- [ ] Breaking change (`!` after type OR `BREAKING CHANGE:` in body)

## Checklist (CLAUDE.md Appendix A excerpt)

- [ ] Single responsibility — the PR does one thing.
- [ ] Tests cover happy / error / edge.
- [ ] Zero lint warnings, strict types.
- [ ] No secrets in code / config / logs.
- [ ] External input schema-validated at the boundary.
- [ ] Audit log for state-changing ops (who / what / when / where / which).
- [ ] Dependencies pinned; no HIGH/CRITICAL CVEs introduced.
- [ ] Commits follow Conventional Commits.
- [ ] Timeouts + retries on every new external call.

## Test plan

<!-- How the reviewer verifies. -->

## Rollback plan

<!-- Delete if pure-docs. Otherwise: how do we revert? -->
PRT_EOF
fi

if create_if_missing "${PROJECT_ROOT}/.github/dependabot.yml" "Dependabot config"; then
  cat > "${PROJECT_ROOT}/.github/dependabot.yml" << 'DEP_EOF'
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly, day: monday, time: "09:00", timezone: Australia/Sydney }
    open-pull-requests-limit: 5
    commit-message: { prefix: chore, include: scope }

  - package-ecosystem: npm
    directory: /
    schedule: { interval: weekly, day: monday, time: "09:00", timezone: Australia/Sydney }
    open-pull-requests-limit: 5
    commit-message: { prefix: chore, include: scope }
    groups:
      production-deps: { dependency-type: production }
      dev-deps: { dependency-type: development }
DEP_EOF
fi

# ── 8. Drift-check workflow ──────────────────────────────────────────
if create_if_missing "${PROJECT_ROOT}/.github/workflows/sync-standards-check.yml" "standards-drift CI job"; then
  cat > "${PROJECT_ROOT}/.github/workflows/sync-standards-check.yml" << 'SYNC_CI_EOF'
name: sync-standards-check

on:
  pull_request:
  push:
    branches: [main]

jobs:
  check:
    uses: uspdan/engineering-standards/.github/workflows/reusable-sync-check.yml@main
    with:
      ref: main
SYNC_CI_EOF
fi

# ── 9. Release-please ────────────────────────────────────────────────
if create_if_missing "${PROJECT_ROOT}/.github/workflows/release-please.yml" "release-please workflow"; then
  cat > "${PROJECT_ROOT}/.github/workflows/release-please.yml" << 'RP_YML_EOF'
name: release-please

on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write

jobs:
  release-please:
    runs-on: ubuntu-24.04
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
RP_YML_EOF
fi

if create_if_missing "${PROJECT_ROOT}/release-please-config.json" "release-please config"; then
  # Detect whether this is a node project; if so use node release-type so
  # package.json's version gets bumped too.
  if [[ -f "${PROJECT_ROOT}/package.json" ]]; then
    RELEASE_TYPE="node"
  else
    RELEASE_TYPE="simple"
  fi
  cat > "${PROJECT_ROOT}/release-please-config.json" << RP_CFG_EOF
{
  "\$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "release-type": "${RELEASE_TYPE}",
  "packages": {
    ".": { "release-type": "${RELEASE_TYPE}", "include-component-in-tag": false }
  },
  "pull-request-title-pattern": "chore(main): release \${version}",
  "changelog-sections": [
    { "type": "feat", "section": "Added" },
    { "type": "fix", "section": "Fixed" },
    { "type": "security", "section": "Security" },
    { "type": "docs", "section": "Changed" },
    { "type": "refactor", "section": "Changed" },
    { "type": "chore", "section": "Changed", "hidden": true },
    { "type": "test", "section": "Changed", "hidden": true }
  ]
}
RP_CFG_EOF
fi

if create_if_missing "${PROJECT_ROOT}/.release-please-manifest.json" "release-please manifest"; then
  # Inherit the current version from package.json if present, else 0.1.0.
  if [[ -f "${PROJECT_ROOT}/package.json" ]]; then
    current=$(grep -oP '"version":\s*"\K[^"]+' "${PROJECT_ROOT}/package.json" | head -1)
    current="${current:-0.1.0}"
  else
    current="0.1.0"
  fi
  echo "{\".\": \"${current}\"}" > "${PROJECT_ROOT}/.release-please-manifest.json"
fi

if create_if_missing "${PROJECT_ROOT}/CHANGELOG.md" "CHANGELOG skeleton"; then
  cat > "${PROJECT_ROOT}/CHANGELOG.md" << 'CHANGELOG_EOF'
# Changelog

All notable changes are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

This file is maintained by release-please. Do not edit manually.

## [Unreleased]
CHANGELOG_EOF
fi

# ── 10. commitlint ───────────────────────────────────────────────────
if create_if_missing "${PROJECT_ROOT}/commitlint.config.cjs" "commitlint config"; then
  cat > "${PROJECT_ROOT}/commitlint.config.cjs" << 'CL_EOF'
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      ['feat', 'fix', 'refactor', 'test', 'docs', 'chore', 'security'],
    ],
    'header-max-length': [2, 'always', 100],
    'subject-case': [2, 'never', ['upper-case', 'pascal-case', 'start-case']],
  },
};
CL_EOF
fi

# ── 11. Pre-commit hook (husky-style, no install required) ──────────
if create_if_missing "${PROJECT_ROOT}/.husky/pre-commit" "pre-commit hook"; then
  cat > "${PROJECT_ROOT}/.husky/pre-commit" << 'HOOK_EOF'
#!/usr/bin/env bash
# Pre-commit hook — local fast-feedback. CI is the authoritative gate.
# Runs lint-staged if available (fast, incremental) and a quick typecheck.
# Bypass with `git commit --no-verify` if truly needed (not recommended).

set -e

if [ -x "node_modules/.bin/lint-staged" ]; then
  node_modules/.bin/lint-staged
fi

if [ -x "node_modules/.bin/tsc" ]; then
  node_modules/.bin/tsc --noEmit --incremental || {
    echo ""
    echo "[pre-commit] typecheck failed — fix before committing."
    echo "[pre-commit] bypass (only when sure): git commit --no-verify"
    exit 1
  }
fi
HOOK_EOF
  chmod +x "${PROJECT_ROOT}/.husky/pre-commit"
fi

# Activate the husky directory if .git exists (one-liner, idempotent).
if [[ -d "${PROJECT_ROOT}/.git" ]]; then
  git -C "${PROJECT_ROOT}" config core.hooksPath .husky
  echo "[OK] git core.hooksPath set to .husky"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "Next steps:"
echo "  1. Review the new .github/ files + CHANGELOG.md"
echo "  2. If you have package.json: add 'lint-staged' + '@commitlint/*' as devDeps"
echo "       npm i -D lint-staged @commitlint/cli @commitlint/config-conventional"
echo "  3. Add a lint-staged config to package.json, e.g.:"
echo "       \"lint-staged\": { \"*.{ts,tsx}\": \"eslint --fix\" }"
echo "  4. Commit everything: 'chore(workflow): adopt engineering-standards workflow bootstrap'"
echo "  5. After first merge to main, release-please will open a chore(release) PR"
echo ""
