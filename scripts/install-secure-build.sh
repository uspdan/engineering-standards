#!/usr/bin/env bash
# install-secure-build.sh — install the secure-build agent team to ~/.claude/.
#
# Run once after cloning engineering-standards, and again whenever you want to
# refresh from this repo. Idempotent; overwrites existing files.
#
# Layout written to ~/.claude/:
#
#   agents/orchestrator.md
#   agents/security-architect.md
#   agents/software-engineer.md
#   agents/defensive-engineer.md
#   agents/code-reviewer.md
#   agents/appsec-reviewer.md
#   agents/qa-engineer.md
#   agents/red-team.md
#   agents/compliance-reviewer.md
#   agents/codex-liaison.md
#   commands/secure-build.md
#   refs/roles/architect.md
#   refs/roles/builder.md
#   refs/roles/defensive.md
#   refs/roles/reviewer.md
#   refs/roles/appsec.md
#   refs/roles/redteam.md
#   refs/roles/qa.md
#   refs/roles/compliance.md
#   refs/roles/codex.md
#   refs/roles/orchestrator.md
#   refs/CLAUDE.md            (copy of canonical CLAUDE.md, so refs/roles/*.md can cite it)
#   refs/CLAUDE.agent.md      (copy of canonical CLAUDE.agent.md)
#   scripts/codex-preflight.sh
#   scripts/reuse-inventory.sh
#
# Existing user files are backed up to ~/.claude/.backups/<timestamp>/ before being
# overwritten so nothing is silently destroyed.
#
# Usage:
#   ./scripts/install-secure-build.sh                # install/refresh from this checkout
#   ./scripts/install-secure-build.sh --dry-run      # show what would change, don't write
#   ./scripts/install-secure-build.sh --force        # skip the prompts (for CI)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER_CLAUDE="${CLAUDE_HOME:-$HOME/.claude}"
DRY_RUN=0
FORCE=0

usage() { sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --force)   FORCE=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

echo "=== Secure-Build Installer ==="
echo "Source: ${REPO_ROOT}"
echo "Target: ${USER_CLAUDE}"
echo "Dry-run: ${DRY_RUN}"
echo

if [[ ! -d "${USER_CLAUDE}" ]]; then
  if [[ ${FORCE} -eq 1 || ${DRY_RUN} -eq 1 ]]; then
    [[ ${DRY_RUN} -eq 0 ]] && mkdir -p "${USER_CLAUDE}"
  else
    read -r -p "${USER_CLAUDE} does not exist. Create it? [y/N] " ans
    [[ "${ans}" == "y" || "${ans}" == "Y" ]] || { echo "aborted"; exit 1; }
    mkdir -p "${USER_CLAUDE}"
  fi
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${USER_CLAUDE}/.backups/${TS}"
[[ ${DRY_RUN} -eq 0 ]] && mkdir -p "${BACKUP_DIR}"

# ── helpers ───────────────────────────────────────────────────────────
copy_file() {
  # $1=src $2=dest
  local src="$1" dest="$2"
  if [[ ! -f "${src}" ]]; then
    echo "[MISS] source not found: ${src}" >&2
    return 1
  fi
  local dest_dir
  dest_dir="$(dirname "${dest}")"
  if [[ -f "${dest}" ]] && diff -q "${src}" "${dest}" >/dev/null 2>&1; then
    echo "[OK]    ${dest#${USER_CLAUDE}/}"
    return 0
  fi
  if [[ ${DRY_RUN} -eq 1 ]]; then
    if [[ -f "${dest}" ]]; then
      echo "[DIFF]  ${dest#${USER_CLAUDE}/}  (would overwrite)"
    else
      echo "[NEW]   ${dest#${USER_CLAUDE}/}"
    fi
    return 0
  fi
  if [[ -f "${dest}" ]]; then
    local rel="${dest#${USER_CLAUDE}/}"
    mkdir -p "${BACKUP_DIR}/$(dirname "${rel}")"
    cp "${dest}" "${BACKUP_DIR}/${rel}"
    echo "[BACKUP] ${rel} → .backups/${TS}/"
  fi
  mkdir -p "${dest_dir}"
  cp "${src}" "${dest}"
  if [[ "${dest}" == *.sh ]]; then chmod +x "${dest}"; fi
  echo "[WROTE] ${dest#${USER_CLAUDE}/}"
}

copy_dir() {
  # $1=src_dir $2=dest_dir   — copies every regular file (top-level only) from src to dest
  local src="$1" dest="$2"
  if [[ ! -d "${src}" ]]; then
    echo "[MISS] source dir not found: ${src}" >&2
    return 1
  fi
  while IFS= read -r -d '' f; do
    local base
    base="$(basename "${f}")"
    copy_file "${f}" "${dest}/${base}"
  done < <(find "${src}" -maxdepth 1 -type f -print0)
}

# ── deploy ────────────────────────────────────────────────────────────
echo "--- agents/ ---"
copy_dir "${REPO_ROOT}/agents" "${USER_CLAUDE}/agents"

echo
echo "--- commands/secure-build.md ---"
copy_file "${REPO_ROOT}/commands/secure-build.md" "${USER_CLAUDE}/commands/secure-build.md"

echo
echo "--- refs/roles/ ---"
copy_dir "${REPO_ROOT}/refs/roles" "${USER_CLAUDE}/refs/roles"

echo
echo "--- refs/ (canonical standards copies for agent citations) ---"
copy_file "${REPO_ROOT}/CLAUDE.md"        "${USER_CLAUDE}/refs/CLAUDE.md"
copy_file "${REPO_ROOT}/CLAUDE.agent.md"  "${USER_CLAUDE}/refs/CLAUDE.agent.md"

echo
echo "--- scripts/ ---"
copy_file "${REPO_ROOT}/scripts/codex-preflight.sh"  "${USER_CLAUDE}/scripts/codex-preflight.sh"
copy_file "${REPO_ROOT}/scripts/reuse-inventory.sh"  "${USER_CLAUDE}/scripts/reuse-inventory.sh"

echo
if [[ ${DRY_RUN} -eq 1 ]]; then
  echo "Dry run complete. No files were written."
else
  # If backup dir is empty (first install), clean it up to avoid clutter.
  if [[ -d "${BACKUP_DIR}" ]] && [[ -z "$(ls -A "${BACKUP_DIR}" 2>/dev/null)" ]]; then
    rmdir "${BACKUP_DIR}"
  fi
  echo "Install complete."
  echo
  echo "Next steps:"
  echo "  1. Confirm codex auth:           codex login"
  echo "  2. Confirm engineering-standards is bootstrapped in your project (CLAUDE.md present)."
  echo "  3. Run the pipeline:             /secure-build <task description>"
fi
