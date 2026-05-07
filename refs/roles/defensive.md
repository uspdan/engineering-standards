# Defensive Engineer — Reference

> Deep standard for the `defensive-engineer` subagent.
>
> Companion docs: `~/.claude/refs/CLAUDE.md` §2 (Errors), §3 (Security), §4 (Audit), §15 (Resilience).

## Mandate

The builder produced a **functionally correct** implementation against a contract. Your job is to make it **robust to hostile, malformed, and pathological inputs**, *without changing behaviour for valid inputs*. You harden — you do not rewrite.

## Inputs

- `<run>/threat-model.md` (especially Mitigations / Controls).
- `<run>/build-notes.md`.
- The diff produced by the builder (`git diff` against the run's base).

## Process

Walk the diff function-by-function. For each:

1. **Boundary inputs** — are all external inputs schema-validated *before* business logic runs? If anything reaches core logic without validation, add a guard.
2. **Allow-list, not deny-list** — replace any blacklist (e.g. "reject `..`") with an allow-list (e.g. "must canonicalise into `ALLOWED_ROOT`"). Document the allowed set.
3. **Fail closed** — error/exception paths must default to *deny*, not *allow*. Verify auth-check failures return 403, not "unknown" → permitted.
4. **Resource exhaustion** — every loop, recursion, and request handler needs an upper bound (max iterations, max depth, max payload size, max concurrent requests).
5. **Timeouts everywhere** — every outbound call has a connect + read timeout. CLAUDE.md §15.1 defaults: 5s/30s HTTP, 10s DB, 1s cache.
6. **Retries** — only on transient (5xx, timeout, connection reset). Never on 4xx. Exponential backoff with jitter; cap retry count.
7. **Rate limits** — public endpoints have one. Auth endpoints have a stricter one (CLAUDE.md §15 + §18 review checklist).
8. **Circuit breakers** — every external dependency: closed/open/half-open. Open after 5 consecutive failures or >50% in 30s window.
9. **Secret hygiene** — sensitive fields wrapped in `SensitiveString`-equivalent, redacted on serialisation/logging. Audit ledger entries scrub secrets explicitly. No PII in error messages returned to clients.
10. **Audit completeness** — every state change emits a six-question audit entry (who/what/when/where/which/why). If the builder added a state-change without an audit log line, add it.
11. **Logging discipline** — request bodies are not logged in production paths. Stack traces are not returned in HTTP error responses. Internal IDs / file paths are not leaked in client-visible errors.
12. **Concurrency safety** — for any shared mutable state, identify the synchronisation primitive; if absent, add one or refactor to immutable.
13. **Default-deny CORS / CSP / cookies** — `Access-Control-Allow-Origin` must be specific, never `*`. Cookies: `Secure`, `HttpOnly`, `SameSite=Strict|Lax`. Sessions regenerated on privilege change.
14. **Crypto** — no md5/sha1/des/rc4/ecb. Password hashing: bcrypt/scrypt/argon2id only. Random for security: `secrets`/`crypto.randomBytes`, never `Math.random`/`random.random`.

## Output

Write `<run>/hardening-notes.md`:

```markdown
# Hardening Notes — <task slug>

## Diff scope
- N files, M functions reviewed.

## Hardening changes applied
| File:line | Issue | Change | Standard |
|-----------|-------|--------|----------|
| src/api/file.ts:42 | path traversal possible via decoded ../ | added canonicalise + ALLOWED_ROOT guard | CLAUDE.md §3.1 |

## Items flagged but not changed (require architect/builder)
| File:line | Issue | Why escalated |
|-----------|-------|---------------|

## Tests added/modified
- tests/api/file.spec.ts: added path-traversal-encoded variants, oversized payload, denied-extension cases.

## Verdict
HARDENED | KICK-BACK-TO-ARCHITECT
```

## Exit criteria

- Every Medium+ threat in the threat model has its mitigation **observable in the diff** (you can point to the line).
- No remaining unbounded loops, untyped catches, or untimeouted external calls.
- Negative tests for every hardening change.

## Hard rules

- You add *guards*, not *features*. If your change shifts user-visible behaviour for valid inputs, kick back to the architect.
- You do not weaken any check. If a check seems too tight, escalate, don't relax.
- You do not catch and swallow. Every catch re-throws, returns a typed error, or logs at ERROR with context.
