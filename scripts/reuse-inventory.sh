#!/usr/bin/env bash
# reuse-inventory.sh — find existing functions/utilities that match a task's
# keywords, both in the current project and across /data/projects, so the
# architect/builder can reuse instead of reinvent.
#
# Usage:
#   reuse-inventory.sh "validate path traversal canonical root"           # space-separated keywords
#   reuse-inventory.sh --keywords "auth jwt verify" --out PATH            # explicit args
#   reuse-inventory.sh --project /data/projects/foundry --keywords "rate limit"
#   reuse-inventory.sh --workspaces-root /data/projects --keywords "..."  # custom workspaces root
#
# Emits a markdown report at $OUT (default: $PROJECT/.claude/runs/<ts>-reuse-inventory/reuse-inventory.md).
#
# What it does:
#   1. Tokenises keywords; drops trivial stop-words.
#   2. ripgrep across the current project for symbol-shaped matches
#      (function defs, class defs, method names, exported identifiers).
#   3. ripgrep across other projects under WORKSPACES_ROOT for the same.
#   4. Sorts by file frequency; reports top candidates with file:line + signature.
#   5. Emits the report. Architect must consult before specifying new code.
#
# Honours .gitignore (rg default). Skips dotfiles, node_modules, venv, dist, build.

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
WORKSPACES_ROOT="${WORKSPACES_ROOT:-/data/projects}"
KEYWORDS=""
OUT=""

usage() {
  sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keywords) KEYWORDS="$2"; shift 2 ;;
    --project)  PROJECT_ROOT="$2"; shift 2 ;;
    --workspaces-root) WORKSPACES_ROOT="$2"; shift 2 ;;
    --out)      OUT="$2"; shift 2 ;;
    -h|--help)  usage ;;
    -*)         echo "Unknown flag: $1" >&2; exit 2 ;;
    *)          KEYWORDS="${KEYWORDS:+${KEYWORDS} }$1"; shift ;;
  esac
done

if [[ -z "${KEYWORDS}" ]]; then
  echo "[ERROR] no keywords supplied. See --help." >&2
  exit 2
fi

if command -v rg >/dev/null 2>&1; then
  SEARCH_BACKEND="rg"
else
  SEARCH_BACKEND="grep"
  echo "[INFO] ripgrep not found; falling back to grep -rE (slower, no .gitignore awareness)" >&2
fi

cd "${PROJECT_ROOT}"

if [[ -z "${OUT}" ]]; then
  TS="$(date -u +%Y%m%dT%H%M%SZ)"
  OUT_DIR="${PROJECT_ROOT}/.claude/runs/${TS}-reuse-inventory"
  mkdir -p "${OUT_DIR}"
  OUT="${OUT_DIR}/reuse-inventory.md"
fi
mkdir -p "$(dirname "${OUT}")"

# Stop-words: noise that shouldn't drive symbol search.
STOPWORDS=" the a an and or of for to from with on in by as is be at it that this these those into over under per via "

declare -a TOKENS=()
for w in ${KEYWORDS}; do
  lw="$(printf '%s' "$w" | tr '[:upper:]' '[:lower:]')"
  if [[ ${#lw} -lt 3 ]]; then continue; fi
  if [[ "${STOPWORDS}" == *" ${lw} "* ]]; then continue; fi
  TOKENS+=("${lw}")
done

if [[ ${#TOKENS[@]} -eq 0 ]]; then
  echo "[ERROR] no usable tokens after stop-word filter." >&2
  exit 2
fi

# Build alternation regex matching symbol-like identifiers containing any token.
# Examples that should match: validatePath, validate_path, PathValidator, path_validator.
TOKEN_RE="$(IFS='|'; echo "${TOKENS[*]}")"

# Symbol-shape patterns. Two variants:
#   PCRE (rg --pcre2)  — used when rg is available; precise.
#   ERE  (grep -rE)    — fallback; broader, with manual --exclude-dir.
PATTERNS_PCRE=(
  "(def|fn|function|func|class|interface|type|const|let|var|public|private|protected|export\s+(?:default\s+)?(?:async\s+)?(?:function|class|const|let))\s+\w*(${TOKEN_RE})\w*"
  "(${TOKEN_RE})\w*\s*[:=]\s*(\(|async\s*\(|function)"
  "(${TOKEN_RE})\w*\s*\("
)

# ERE-safe approximations: drop \s and (?:...); use [[:space:]] and plain (...).
PATTERNS_ERE=(
  "(def|fn|function|func|class|interface|type|const|let|var|public|private|protected|export[[:space:]]+(default[[:space:]]+)?(async[[:space:]]+)?(function|class|const|let))[[:space:]]+[A-Za-z0-9_]*(${TOKEN_RE})[A-Za-z0-9_]*"
  "(${TOKEN_RE})[A-Za-z0-9_]*[[:space:]]*[:=][[:space:]]*([(]|async[[:space:]]*[(]|function)"
  "(${TOKEN_RE})[A-Za-z0-9_]*[[:space:]]*[(]"
)

RG_EXCLUDES=(
  --glob '!**/node_modules/**'
  --glob '!**/dist/**'
  --glob '!**/build/**'
  --glob '!**/.venv/**'
  --glob '!**/venv/**'
  --glob '!**/__pycache__/**'
  --glob '!**/target/**'
  --glob '!**/.next/**'
  --glob '!**/coverage/**'
  --glob '!**/*.min.js'
  --glob '!**/*.bundle.js'
)

GREP_EXCLUDES=(
  --exclude-dir=node_modules
  --exclude-dir=dist
  --exclude-dir=build
  --exclude-dir=.venv
  --exclude-dir=venv
  --exclude-dir=__pycache__
  --exclude-dir=target
  --exclude-dir=.next
  --exclude-dir=coverage
  --exclude-dir=.git
  --exclude='*.min.js'
  --exclude='*.bundle.js'
)

run_search() {
  # $1 = root path
  local root="$1"
  if [[ "${SEARCH_BACKEND}" == "rg" ]]; then
    for pat in "${PATTERNS_PCRE[@]}"; do
      rg --pcre2 -i -n --no-messages -H \
         "${RG_EXCLUDES[@]}" \
         -e "${pat}" \
         "${root}" 2>/dev/null || true
    done
  else
    for pat in "${PATTERNS_ERE[@]}"; do
      grep -rEHIn -i \
        "${GREP_EXCLUDES[@]}" \
        --include='*.py' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
        --include='*.rs' --include='*.go' --include='*.rb' --include='*.java' --include='*.kt' \
        --include='*.cs' --include='*.php' --include='*.sh' --include='*.swift' \
        -e "${pat}" \
        "${root}" 2>/dev/null || true
    done
  fi
}

# Run searches.
PROJECT_HITS="$(run_search "${PROJECT_ROOT}" | sort -u || true)"

CROSS_HITS=""
if [[ -d "${WORKSPACES_ROOT}" ]]; then
  # Search siblings only — exclude the current project.
  for sib in "${WORKSPACES_ROOT}"/*/; do
    [[ -d "${sib}" ]] || continue
    sibreal="$(realpath "${sib}")"
    pjreal="$(realpath "${PROJECT_ROOT}")"
    if [[ "${sibreal}" == "${pjreal}" ]]; then continue; fi
    CROSS_HITS="${CROSS_HITS}$(run_search "${sib}" 2>/dev/null || true)
"
  done
  CROSS_HITS="$(printf '%s' "${CROSS_HITS}" | sort -u | sed '/^$/d' || true)"
fi

# Top files by frequency (helps architect pick which to read first).
top_files() {
  local hits="$1" limit="$2"
  printf '%s\n' "${hits}" | awk -F: 'NF>=2 {print $1}' | sort | uniq -c | sort -rn | head -n "${limit}"
}

# Cap the per-section line counts so the report stays scannable.
sample() {
  local hits="$1" limit="$2"
  printf '%s\n' "${hits}" | head -n "${limit}"
}

{
  echo "# Reuse Inventory"
  echo
  echo "- Generated: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
  echo "- Project: \`${PROJECT_ROOT}\`"
  echo "- Workspaces root: \`${WORKSPACES_ROOT}\`"
  echo "- Keywords: \`${KEYWORDS}\`"
  echo "- Tokens used: \`${TOKEN_RE}\`"
  echo
  echo "## How to use this report"
  echo
  echo "Architect: scan **In-project candidates** first — anything matching by name *must* be opened and assessed for reuse before specifying new code. Cross-project candidates are secondary references; reuse them only when they would land as a shared lib or copied with attribution to the source project."
  echo
  echo "Builder: any new function whose intent overlaps a candidate listed below must be justified in the run's \`summary.md\` (e.g. \"different trust boundary\", \"upstream lib unmaintained\")."
  echo
  echo "## In-project candidates (top files by hit count)"
  echo
  if [[ -z "${PROJECT_HITS}" ]]; then
    echo "_No matches in current project._"
  else
    echo '```'
    top_files "${PROJECT_HITS}" 25
    echo '```'
    echo
    echo "### Sample matches (first 60 lines)"
    echo
    echo '```'
    sample "${PROJECT_HITS}" 60
    echo '```'
  fi
  echo
  echo "## Cross-project candidates (siblings under ${WORKSPACES_ROOT})"
  echo
  if [[ -z "${CROSS_HITS}" ]]; then
    echo "_No matches in sibling projects._"
  else
    echo '```'
    top_files "${CROSS_HITS}" 25
    echo '```'
    echo
    echo "### Sample matches (first 80 lines)"
    echo
    echo '```'
    sample "${CROSS_HITS}" 80
    echo '```'
  fi
  echo
} > "${OUT}"

echo "[reuse-inventory] wrote ${OUT}"
