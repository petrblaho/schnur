# CI: Parallelize Jobs by Removing the Setup Gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut CI wall time by letting `test`, `lint`, `format`, `typecheck` run in parallel from t=0 instead of gating them on a `setup` job that does no work the consumers do not already redo.

**Architecture:** Delete the `setup` job and its `needs: setup` gates. Designate the `test` job as the owner of the `deps`+`_build` cache (it always needs deps, DB, and a full compile) and add an explicit `mix compile --warnings-as-errors` gate there. `format`/`lint`/`typecheck` remain self-sufficient cache consumers.

**Tech Stack:** GitHub Actions (`actions/cache@v4`, `erlef/setup-beam@v1`), Elixir/Mix, Postgres service container.

## Global Constraints

- Elixir `1.20.3`, OTP `29.0.5`; `MIX_ENV: test` globally.
- Required status checks on `main` (verified via `gh api`): **Test, Format, Lint, Typecheck, Lint Commit Messages**. "Setup and Compile" is NOT required — safe to remove.
- `enforce_admins: true`, `allow_force_pushes: false` on `main` — never force-push `main`; feature-branch force-push is fine.
- `actions/cache@v4`: saves only on primary-key miss; keys immutable.
- Commit style: Scoped Commits `<scope>: <Capitalized description>`.

## Measured Baseline (run 32738597289)

- Wall ~69s. Critical path: `setup` 17s → ~7s provisioning gap → `Test` ~40s (Postgres init 19s + stop 4s). Compile ~1s in every job (cache already effective; no recompilation to fix).
- Target: ~45s wall, bounded by the Test job.

---

### Task 0: Branch-protection safety check (DONE during planning)

- [x] `gh api repos/petrblaho/schnur/branches/main/protection` → required checks are Test/Format/Lint/Typecheck/Lint Commit Messages. "Setup and Compile" not required. Proceed.

### Task 1: Make `test` own the deps cache and hold the compile gate

**Files:** Modify `.github/workflows/ci.yml` (test job).

- [ ] Add `id: mix-cache` and `restore-keys` to the test job's "Restore dependencies cache" step.
- [ ] Gate `Install dependencies` with `if: steps.mix-cache.outputs.cache-hit != 'true'`.
- [ ] Add a `mix compile --warnings-as-errors` step before "Set up database".
- [ ] Validate YAML.
- [ ] Commit: `ci: make test job own deps cache and compile gate`

### Task 2: Remove the `setup` job and all `needs: setup`

**Files:** Modify `.github/workflows/ci.yml`.

- [ ] Delete the `setup` job.
- [ ] Remove `needs: setup` from `test`, `format`, `lint`, `typecheck`.
- [ ] Validate YAML.
- [ ] Commit: `ci: run checks in parallel by removing setup gate`

### Task 3: Validate on a PR

- [ ] Push branch, open PR.
- [ ] Wait for CI; confirm Test/Format/Lint/Typecheck all pass and measure wall time vs 69s.
- [ ] Prove compile gate: temporarily add an unused-variable warning, confirm Test fails at compile step, then remove and confirm green.
- [ ] Confirm cold-start correctness (jobs self-sufficient in parallel).
- [ ] Leave PR for review (no auto-merge).

## Self-Review

- Goal covered by Tasks 1-2; validation by Task 3.
- Cache-owner correctness: only `test` saves the cache after `setup` is gone; consumers restore read-only and don't need `_build`.
- No placeholders; all edits shown at execution time with exact before/after.

See conversation context for full rationale and measurements.
