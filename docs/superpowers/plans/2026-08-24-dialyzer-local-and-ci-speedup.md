# Dialyzer: Local Parity + CI Speedup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the local `pre-push` hook catch the exact type errors CI catches (by running dialyzer in the `test` environment), and stop CI's Typecheck job from rebuilding the dialyzer PLT on every run.

**Architecture:** Two independent changes. (1) The `pre-push` hook runs `MIX_ENV=test mix dialyzer` so `test/support/*` files (which `use ExUnit.CaseTemplate`) are analyzed locally — matching CI's `MIX_ENV: test`. (2) The CI Typecheck job gets a dedicated PLT prebuild step and a cache key that includes `mix.exs`, so a `plt_add_apps`/dialyzer-config change forces a fresh, correctly-saved PLT instead of restoring a stale one and rebuilding inline every run.

**Tech Stack:** Bash git hooks, GitHub Actions (`actions/cache@v4`, `erlef/setup-beam@v1`), Elixir/Mix, Dialyxir.

## Global Constraints

- Elixir `1.20.3`, OTP `29.0.5` (pinned in CI `env:` and `mise.toml`).
- CI runs under `MIX_ENV: test` globally (`.github/workflows/ci.yml:13`).
- Dialyzer config lives in `mix.exs` `project/0`: `dialyzer: [plt_local_path: ".plts", plt_core_path: ".plts", plt_add_apps: [:ex_unit]]`.
- `.plts/` is git-ignored; PLT files are env-specific (`..._deps-dev.plt` vs `..._deps-test.plt`).
- Git hooks live in `.githooks/` (`core.hooksPath = .githooks`).
- Commit style: Scoped/Conventional Commits — `<scope>: <Capitalized description>`.
- `actions/cache@v4` behavior: a cache entry is **saved** in the post-job step only when the primary `key` produced a **miss** at restore time; entries are immutable per key. A stable key therefore never re-saves.

## Baseline (measured, run 32736930310 on main, PLT "warm")

- Typecheck: **153s** (bottleneck) — Setup 18s, Test 34s, Lint 13s, Format 14s.

---

### Task 1: Run dialyzer in test env in the pre-push hook (local parity)

**Files:** Modify `.githooks/pre-push:12-16`

- [ ] Replace the dialyzer block with `MIX_ENV=test mix dialyzer`.
- [ ] Verify `bash -n` + executable bit.
- [ ] Manually run `MIX_ENV=test mix dialyzer` → passes.
- [ ] Prove gate trips with a temporary bad `@spec` probe in `data_case.ex`, then remove it.
- [ ] Commit: `hooks: run dialyzer in test env on pre-push to match CI`

### Task 2: Add `dialyzer.build` alias + prebuild PLT in CI, keyed on mix.exs

**Files:** Modify `mix.exs` aliases; modify `.github/workflows/ci.yml` typecheck job.

- [ ] Add alias `"dialyzer.build": ["dialyzer --plt"]`.
- [ ] Change PLT cache key to `hashFiles('mix.lock', 'mix.exs')`.
- [ ] Add `Build PLT` step (`if: cache-hit != 'true'`) running `mkdir -p .plts && mix dialyzer.build`, before `Run dialyzer`.
- [ ] Validate YAML; `mix precommit` passes.
- [ ] Commit: `ci: prebuild dialyzer plt and key cache on mix.exs to cut typecheck time`

### Task 3: Validate the CI speedup end-to-end via PR

- [ ] Push branch, open PR.
- [ ] Cold run: all green, PLT built once + saved.
- [ ] Warm run (throwaway commit): Typecheck drops toward analysis-only, `Build PLT` skipped.
- [ ] Drop throwaway commit; final green; leave for review.

See conversation context for full step-by-step detail and rationale.
