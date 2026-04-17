<!--
PR template. Fill out honestly — this becomes the squash-merge commit
message. Delete sections that don't apply.

Title format (Conventional Commits, enforced by commitlint):
  <type>(<scope>): <description>
  e.g. feat(licence): add readonly interstitial on 402
-->

## Summary

<!-- What changed and why. Two to four sentences. -->

## Motivation

<!-- What problem does this solve? Link to issue / backlog entry / incident if any. -->

## Scope of change

- [ ] Docs only
- [ ] Infra / tooling
- [ ] New feature
- [ ] Bug fix
- [ ] Security patch
- [ ] Breaking change (requires `!` after type OR `BREAKING CHANGE:` in body)

## Checklist (CLAUDE.md Appendix A excerpt)

- [ ] Single responsibility — the PR does one thing.
- [ ] Tests cover happy path, error path, edge case.
- [ ] Zero lint warnings, strict types, no `any` / `# type: ignore`.
- [ ] No secrets in code / config / logs.
- [ ] External input is schema-validated at the boundary.
- [ ] Audit log captures state-changing operations (who / what / when / where / which).
- [ ] Dependencies pinned; no known HIGH/CRITICAL CVEs introduced.
- [ ] Commits follow Conventional Commits.
- [ ] Timeouts + retries on every new external call.
- [ ] If this changes an ADR-worthy decision — ADR added under `docs/adr/`.

## Test plan

<!-- How the reviewer verifies this works. -->

- [ ] `npm test` (or project-specific equivalent) green.
- [ ] Manual smoke: …

## Rollback plan

<!-- Delete if pure-docs. For code changes: how do we revert if this breaks prod? -->
