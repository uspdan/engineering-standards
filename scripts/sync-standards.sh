#!/usr/bin/env bash
# sync-standards.sh — pull canonical standards files into a downstream repo.
#
# Sources (priority order):
#   1. Local path via STANDARDS_LOCAL_PATH env var — for offline work.
#   2. Remote via HTTPS — default behaviour, no dependencies.
#        Default URL: https://raw.githubusercontent.com/uspdan/engineering-standards/<ref>/
#
# Modes:
#   (default) — overwrite any drifted local files with the canonical copies.
#   --check   — exit 1 on drift; don't write anything. Used by CI.
#
# Flags:
#   --ref <sha-or-tag>  Pin to a specific remote commit / tag. Default: main.
#   --remote <url>      Override the remote base URL.
#   --check             Check-only; non-zero exit on drift.
#
# Files synced: CLAUDE.md, CLAUDE.agent.md, LEARNINGS.md.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHECK_ONLY=0
REF="main"
REMOTE="https://raw.githubusercontent.com/uspdan/engineering-standards"
FILES=(CLAUDE.md CLAUDE.agent.md LEARNINGS.md)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    --ref) REF="$2"; shift 2 ;;
    --remote) REMOTE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

# Fetch `${1}` → `${2}`. Prefers STANDARDS_LOCAL_PATH; falls back to remote.
fetch_file() {
  local name="$1"
  local dest="$2"

  if [[ -n "${STANDARDS_LOCAL_PATH:-}" && -f "${STANDARDS_LOCAL_PATH}/${name}" ]]; then
    cp "${STANDARDS_LOCAL_PATH}/${name}" "${dest}"
    return 0
  fi

  local url="${REMOTE}/${REF}/${name}"
  if ! curl -fsSL --max-time 15 -o "${dest}" "${url}"; then
    echo "[ERROR] Failed to fetch ${url}" >&2
    return 1
  fi
}

drift_count=0
updated_count=0
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

for filename in "${FILES[@]}"; do
  target="${PROJECT_ROOT}/${filename}"
  fresh="${tmpdir}/${filename}"

  if ! fetch_file "${filename}" "${fresh}"; then
    echo "[SKIP] ${filename} — source unavailable"
    continue
  fi

  if [[ -f "${target}" ]] && diff -q "${target}" "${fresh}" > /dev/null 2>&1; then
    echo "[OK] ${filename} is up to date"
    continue
  fi

  if [[ "${CHECK_ONLY}" == 1 ]]; then
    echo "[DRIFT] ${filename} differs from canonical @ ${REF}"
    diff -u "${target:-/dev/null}" "${fresh}" | head -40 || true
    drift_count=$((drift_count + 1))
  else
    cp "${fresh}" "${target}"
    echo "[UPDATED] ${filename}"
    updated_count=$((updated_count + 1))
  fi
done

if [[ "${CHECK_ONLY}" == 1 ]]; then
  if [[ "${drift_count}" -gt 0 ]]; then
    echo "" >&2
    echo "Drift detected on ${drift_count} file(s). Run scripts/sync-standards.sh (without --check) to fix." >&2
    exit 1
  fi
  echo "All standards files in sync with ${REMOTE}/${REF}"
else
  echo ""
  echo "Updated ${updated_count} file(s). Review + commit the diff."
fi
