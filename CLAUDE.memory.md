# CLAUDE.memory.md — Project Memory

> This file captures project-specific learnings, patterns, gotchas, and decisions
> that Claude Code should factor into all future work on this project.
>
> **This file is append-friendly and evolves over time.**
> Entries are never deleted — only superseded with a `[SUPERSEDED by #N]` tag.
> Promoted entries are tagged `[PROMOTED to central LEARNINGS.md]`.

---

## HOW TO USE THIS FILE

Claude Code reads this file automatically. When working on this project:

1. **Before coding**: Check relevant sections for known pitfalls and patterns.
2. **After completing a task**: If you discovered something non-obvious, append it.
3. **After a bug fix**: Record what went wrong and why — prevent recurrence.
4. **After a review**: If feedback revealed a gap, capture the learning.

Entries use a consistent format for searchability:

```
### MEM-NNNN: Short title
- **Date**: YYYY-MM-DD
- **Context**: What were we doing when we learned this
- **Learning**: The actual insight — specific, actionable, not vague
- **Evidence**: Link to PR, commit, incident, or conversation
- **Tags**: [area] [severity] [pattern]
```

---

## PATTERNS — What works in this project

> Proven approaches. Claude Code should default to these unless explicitly overridden.

### MEM-0001: Example — Database connection pooling
- **Date**: 2026-XX-XX
- **Context**: Initial setup of database layer
- **Learning**: PgBouncer in transaction mode with pool size = (2 × vCPU) + 1 performs best for this workload. Session mode caused connection starvation under load.
- **Evidence**: PR #42, load test results in docs/benchmarks/
- **Tags**: [infra] [database] [performance]

---

## GOTCHAS — What has bitten us

> Non-obvious failure modes. Claude Code should actively avoid these.

### MEM-0002: Example — Timezone handling in audit logs
- **Date**: 2026-XX-XX
- **Context**: Audit log timestamps were inconsistent across services
- **Learning**: Node's `Date.toISOString()` always emits UTC but the ORM was storing local server time. All timestamps must go through `shared/utils/timestamp.ts` which normalises to UTC before persistence.
- **Evidence**: Incident #7, PR #58
- **Tags**: [bug] [audit] [time]

---

## DECISIONS — Why we chose X over Y

> Architectural choices with rationale. Prevents relitigating settled decisions.
> For major decisions, link to the full ADR in `docs/adr/`.

### MEM-0003: Example — Chose Zod over Joi for validation
- **Date**: 2026-XX-XX
- **Context**: Needed request validation for API layer
- **Learning**: Zod chosen over Joi because: TypeScript-native type inference eliminates duplicate type definitions, tree-shakes better (38KB vs 145KB), and `.transform()` allows parse-and-transform in one step. Joi has better error messages out of the box but Zod's are good enough with custom error maps.
- **Evidence**: ADR-003, PR #12
- **Tags**: [decision] [api] [validation]

---

## DEBT — Known shortcuts and their remediation plan

> Technical debt that Claude Code should be aware of but not fix without being asked.
> Each entry has a priority and a rough remediation path.

### MEM-0004: Example — Auth middleware skips WebSocket connections
- **Date**: 2026-XX-XX
- **Context**: WebSocket support was added under time pressure
- **Learning**: The auth middleware only covers HTTP routes. WebSocket connections validate the initial handshake token but don't re-validate on reconnect. This is acceptable for internal services but must be fixed before exposing WebSocket endpoints publicly.
- **Priority**: Medium — blocks public WebSocket API
- **Remediation**: Implement token refresh check in WebSocket heartbeat handler
- **Evidence**: PR #71, ticket PROJ-234
- **Tags**: [debt] [auth] [websocket]

---

## PERFORMANCE — Benchmarks and capacity observations

> Measured performance characteristics. Prevents premature optimisation and
> guides capacity planning.

### MEM-0005: Example — Bulk import throughput
- **Date**: 2026-XX-XX
- **Context**: Load testing the CSV import endpoint
- **Learning**: Batch inserts of 500 rows/transaction hit the sweet spot: 12,000 rows/sec. At 1000 rows/transaction, WAL pressure causes 3x latency spikes. At 100 rows/transaction, overhead dominates. The bottleneck is PostgreSQL WAL fsync, not application CPU.
- **Evidence**: docs/benchmarks/bulk-import-2026-XX-XX.md
- **Tags**: [performance] [database] [import]

---

## DEPENDENCIES — External dependency notes

> Quirks, version constraints, and known issues with third-party dependencies.

### MEM-0006: Example — sharp@0.33.x breaks on Alpine with vips < 8.15
- **Date**: 2026-XX-XX
- **Context**: Container build failed after dependency update
- **Learning**: sharp 0.33.x requires libvips >= 8.15. The Alpine 3.19 base image ships 8.14. Either pin sharp@0.32.x or use Alpine 3.20+. We're pinning sharp until the next base image upgrade cycle.
- **Evidence**: PR #89, sharp changelog
- **Tags**: [dependency] [container] [image-processing]

---

## ENVIRONMENT — Infrastructure and deployment notes

> Things that are true about our deployment environment that affect code decisions.

### MEM-0007: Example — Staging DB has 10x less memory than prod
- **Date**: 2026-XX-XX
- **Context**: Query that passed staging load tests failed in prod
- **Learning**: Staging PostgreSQL has 2GB RAM vs prod's 16GB. Queries that fit in shared_buffers in prod cause disk I/O in staging, making staging load tests unreliable for memory-bound queries. For queries touching >100K rows, validate the query plan against prod-like `work_mem` settings.
- **Evidence**: Incident #12
- **Tags**: [environment] [database] [testing]

---

## ROLLBACK LOG — What we rolled back and why

> Quick reference for "we tried this and it failed in production."

### MEM-0008: Example — Connection pool hot-reload
- **Date**: 2026-XX-XX
- **Context**: Attempted to add config hot-reload for DB pool size
- **Learning**: Hot-reloading the connection pool caused a 2-second request stall as existing connections drained. Under load, this cascaded into timeout failures across 3 downstream services. Connection pool config changes require a rolling restart, not hot-reload.
- **Evidence**: Incident #15, rollback PR #102
- **Tags**: [rollback] [database] [config]
