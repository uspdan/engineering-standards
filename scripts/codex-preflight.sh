#!/usr/bin/env bash
# codex-preflight.sh — run `codex review` against the current change set with
# the engineering-standards review prompt, and capture the transcript so the
# codex-liaison agent can route findings back to the right specialist.
#
# Used by:
#   - The codex-liaison subagent in the secure-build pipeline.
#   - Optional CI gate before merge.
#
# Modes (auto-selected unless overridden):
#   1. --uncommitted        — staged + unstaged + untracked (default if dirty tree)
#   2. --base <branch>      — diff vs base branch (default if clean tree on a feature branch)
#   3. --commit <sha>       — review a single commit
#
# Usage:
#   codex-preflight.sh                                 # auto-detect mode
#   codex-preflight.sh --base main                     # explicit base
#   codex-preflight.sh --uncommitted                   # explicit uncommitted
#   codex-preflight.sh --commit HEAD~1                 # one commit
#   codex-preflight.sh --out path/to/dir               # transcript output dir
#   codex-preflight.sh --model gpt-5-codex             # model override
#   codex-preflight.sh --advisory                      # never fail on findings
#
# Exit codes:
#   0  — codex review completed; output written. Findings still need parsing by liaison.
#   1  — codex CLI not installed.
#   2  — invalid arguments.
#   3  — codex run failed (network, auth, internal error).
#
# The script does NOT decide pass/fail from the review content — that's the
# liaison agent's job. It returns 0 as long as the review ran cleanly.

set -euo pipefail

CODEX_BIN="${CODEX_BIN:-$(command -v codex || true)}"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
OUT_DIR=""
MODE=""
MODE_ARG=""
MODEL="${CODEX_PREFLIGHT_MODEL:-}"
ADVISORY=0
EXTRA_PROMPT=""

usage() {
  sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uncommitted)        MODE="uncommitted"; shift ;;
    --base)               MODE="base"; MODE_ARG="$2"; shift 2 ;;
    --commit)             MODE="commit"; MODE_ARG="$2"; shift 2 ;;
    --out)                OUT_DIR="$2"; shift 2 ;;
    --model)              MODEL="$2"; shift 2 ;;
    --advisory)           ADVISORY=1; shift ;;
    --extra-prompt)       EXTRA_PROMPT="$2"; shift 2 ;;
    -h|--help)            usage ;;
    *)                    echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "${CODEX_BIN}" || ! -x "${CODEX_BIN}" ]]; then
  echo "[ERROR] codex CLI not found on PATH. Install: npm i -g @openai/codex" >&2
  exit 1
fi

cd "${PROJECT_ROOT}"

# Auto-detect mode if not specified.
if [[ -z "${MODE}" ]]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[ERROR] not inside a git repository; pass --commit or --base explicitly, or cd into the repo" >&2
    exit 2
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    MODE="uncommitted"
  else
    # Default base: prefer main, fall back to master.
    if git show-ref --verify --quiet refs/heads/main; then
      MODE="base"; MODE_ARG="main"
    elif git show-ref --verify --quiet refs/heads/master; then
      MODE="base"; MODE_ARG="master"
    else
      MODE="commit"; MODE_ARG="HEAD"
    fi
  fi
fi

# Output dir default: .claude/runs/<ts>-codex-preflight/ at project root.
if [[ -z "${OUT_DIR}" ]]; then
  TS="$(date -u +%Y%m%dT%H%M%SZ)"
  OUT_DIR="${PROJECT_ROOT}/.claude/runs/${TS}-codex-preflight"
fi
mkdir -p "${OUT_DIR}"

TRANSCRIPT="${OUT_DIR}/codex-transcript.md"
LAST_MESSAGE="${OUT_DIR}/codex-last-message.txt"
META="${OUT_DIR}/codex-meta.json"

# Prompt sent to codex review. Tailored to surface the same kinds of issues
# our specialist agents look for, so kickbacks are minimised. Engineering
# standards live at the project root in CLAUDE.md.
read -r -d '' PROMPT <<'EOF' || true
Review this change set against the project's engineering standards in CLAUDE.md.
For every finding, output:

  [SEVERITY] <file>:<line> — <one-line issue>
    Why it matters: <impact>
    Fix: <concrete recommendation>
    Category: <correctness|security|design|maintainability|test|performance|docs>

Severity values: BLOCKER, MAJOR, MINOR, NIT.

Focus areas, in priority order:

1. Security & logic flaws (OWASP Top 10): injection (SQL/command/path/template),
   secrets in code, broken auth/authz, unvalidated external input reaching core
   logic, weak crypto (md5/sha1/des/Math.random), unsafe deserialisation,
   missing rate limits, CORS wildcards, SSRF, unsafe redirects.
2. Correctness: edge cases, off-by-one, race conditions, resource leaks,
   null/empty/boundary handling, partial-failure paths, type mismatches across
   boundaries.
3. Standards adherence (CLAUDE.md): typed errors (no empty catches), schema
   validation at boundaries, parameterised queries, no hardcoded secrets, no
   files >300 lines, no functions >50 lines, dependency direction (core has no
   infra imports), audit logging for state changes, sensitive data redaction,
   explicit timeouts on external calls, retry with backoff.
4. Tests: missing happy/error/edge tests, deterministic, negative-path coverage
   (rejection of malformed input, denied unauthorised access).
5. Maintainability: naming clarity, magic numbers, dead code, duplication.

End with a single line:

  VERDICT: APPROVED | KICK-BACK

Output APPROVED only if there are zero BLOCKER and zero MAJOR findings.
EOF

if [[ -n "${EXTRA_PROMPT}" ]]; then
  PROMPT="${PROMPT}

Additional context for this run:
${EXTRA_PROMPT}"
fi

# Build codex review args.
CODEX_ARGS=()
case "${MODE}" in
  uncommitted) CODEX_ARGS+=(--uncommitted) ;;
  base)        CODEX_ARGS+=(--base "${MODE_ARG}") ;;
  commit)      CODEX_ARGS+=(--commit "${MODE_ARG}") ;;
  *)           echo "[ERROR] invalid mode: ${MODE}" >&2; exit 2 ;;
esac

if [[ -n "${MODEL}" ]]; then
  CODEX_ARGS+=(-c "model=\"${MODEL}\"")
fi

CODEX_ARGS+=(--title "secure-build preflight (${MODE} ${MODE_ARG})")

# Run codex review. Capture both the streaming transcript and the final message.
echo "[codex-preflight] mode=${MODE} arg=${MODE_ARG} project=${PROJECT_ROOT}"
echo "[codex-preflight] transcript -> ${TRANSCRIPT}"

set +e
"${CODEX_BIN}" review "${CODEX_ARGS[@]}" "${PROMPT}" \
  > "${TRANSCRIPT}" 2>&1
RC=$?
set -e

# codex review writes its summary to stdout; the last "VERDICT:" line is what
# we key on. If the run errored, surface that.
if [[ ${RC} -ne 0 ]]; then
  echo "[codex-preflight] codex exited with rc=${RC}" >&2
  if [[ ${ADVISORY} -eq 1 ]]; then
    echo "[codex-preflight] --advisory: returning 0 despite codex error"
  else
    exit 3
  fi
fi

# Extract last "VERDICT:" line (case-insensitive) for convenience.
VERDICT=""
if [[ -f "${TRANSCRIPT}" ]]; then
  VERDICT="$(grep -iE '^VERDICT:' "${TRANSCRIPT}" | tail -1 || true)"
fi
[[ -z "${VERDICT}" ]] && VERDICT="VERDICT: UNKNOWN"

# Copy the trailing few lines as a quick "last message" pointer.
tail -50 "${TRANSCRIPT}" > "${LAST_MESSAGE}" || true

# Lightweight metadata for the liaison agent.
cat > "${META}" <<JSON
{
  "mode": "${MODE}",
  "mode_arg": "${MODE_ARG}",
  "project_root": "${PROJECT_ROOT}",
  "transcript": "${TRANSCRIPT}",
  "verdict_line": $(printf '%s' "${VERDICT}" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))' 2>/dev/null || echo '""'),
  "exit_code": ${RC},
  "advisory": ${ADVISORY}
}
JSON

echo "[codex-preflight] done. ${VERDICT}"
echo "[codex-preflight] artifacts in ${OUT_DIR}"
