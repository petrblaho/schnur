# Schnur Core Architecture & Scribe Bot Design (v2)

## Overview
Schnur is a collaborative note-taking web application for tabletop RPG campaigns. It provides a low-friction, real-time chat-like interface where players append small, timestamped notes. In the background, an LLM (the "Scribe") continuously processes these notes to build and maintain a structured, interconnected wiki of the campaign's lore (characters, places, items, events).

## Core Principles
1. **Append-Only Player Input:** Players interact by appending new `Note` records. Editing notes is forbidden in this phase to simplify the Scribe state machine.
2. **Append-Only Correction:** If the Scribe makes a mistake, players do not edit the wiki directly. They write a new `Note` (e.g., "Actually, Bob is a baker, not a blacksmith"), and the Scribe processes it to update the wiki.
3. **Embedded Syntax is the Source of Truth; Edges are a Derived Cache:** Relationships live inside the LLM-generated Node text using an embedded syntax (`[relationship:: [[Node Name]]]`). The text is the single source of truth. On **write**, the backend parses the text and materializes an `Edge` cache table used for fast lookups (backlinks, "Known Connections"). The cache is fully rebuildable from text; if it disagrees, text wins.
4. **Destructive/Structural Ops are Deterministic, Not LLM-Interpreted:** Additive/corrective changes flow through the LLM (via Notes). Structural mutations (merge, archive) are **explicit UI actions** executed deterministically. The Scribe may only *suggest* them; a human click executes them. (Execution deferred — see Scope.)

## Scope (v1 vs later)
**In v1:**
- Data model, Scribe loop (relevance + update calls), edge-cache parse-on-write, read-path rendering, real-time UI.
- `NodeAction` + `NodeVersion` audit/versioning tables.
- Scribe *suggesting* merges/archives in its Note (read-only suggestion; no execution).

**Deferred to its own spec:**
- Merge/archive **execution** (edge migration across nodes, content concatenation + LLM rephrase, multi-node transactional updates under optimistic lock). High-cost, high-risk, touches every core invariant — warrants a dedicated design pass.
- Job cancel/coalescing optimization.
- Direct player-authored entity links.
- Prompt-injection hardening beyond a trusted friends-group audience.
- Multiple Scribes per Game (schema anticipates it; only one global Scribe now).

## Architecture
- **Frontend/UI:** Phoenix LiveView for real-time updates. Continuous chat stream for raw notes + TiddlyWiki-style sidebar/tab system for browsing the wiki. Broadcasts are scoped per `Game`.
- **Backend:** Phoenix (Elixir) + Ecto on **PostgreSQL**. (Chosen over SQLite: the workload is concurrent writers — LiveView note inserts, Oban polling, Node updates — and Postgres removes single-writer-lock contention as a non-question. Scale is small; this is about avoiding an entire class of write-lock issues, not raw throughput.)
- **IDs:** **UUIDv7** for all primary keys. Time-ordered, so IDs double as a chronological ordering key for Notes.
- **Background Processing:** Oban, **`concurrency: 1` per Game** (per-Game queue/partition). This serializes all Scribe work for a Game and thereby guarantees processing order matches append order without extra coordination.

## Data Model

### Author polymorphism (two nullable FKs + CHECK)
Notes and audit records are authored by either a `User` or the `Scribe`. **No Rails-style string polymorphism** (Ecto has none, and it reintroduces the unenforced string-reference problem we explicitly avoid for edges). Instead: two nullable foreign keys with a DB CHECK constraint that exactly one is non-null.

- `User`: human author (auth/credentials to be expanded in a future spec).
- `Scribe`: its own type (not a `User`). Fields anticipate per-Game config (model, provider, credentials, prompt). One global Scribe for now.

### Tables
- **`Game`** — container for a campaign/world.
- **`User`** — human author.
- **`Scribe`** — LLM author (own type; distinct fields from User).
- **`Note`** — raw, immutable, timestamped log entry in a `Game`.
  - `game_id` (FK)
  - `user_id` (FK, nullable) / `scribe_id` (FK, nullable) — CHECK: exactly one non-null.
  - `kind` — `:player` (untrusted raw input) | `:scribe` (LLM-authored explanation, posted to chat).
    - Guards the trust boundary: `:scribe` notes must never be re-fed to the LLM as player lore (avoids self-ingestion feedback loop).
  - `body` (text)
  - inserted_at (UUIDv7 already time-orders)
- **`Node`** — a wiki entity. Belongs to a `Game`. Holds LLM-generated text (with embedded relationship syntax).
  - `game_id` (FK)
  - `name`
  - `normalized_name` — downcase+trim.
  - **Unique index `(game_id, normalized_name)`** — soft-merge safety net against LLM-created duplicates ("Garrick" vs "garrick").
  - `body` (text — source of truth for relationships)
  - `lock_version` (integer) — **optimistic locking**. A stale Scribe write (e.g., a late-returning LLM call landing after a newer job) fails instead of clobbering. This is the correctness guarantee; per-Game concurrency=1 is the ordering guarantee.
  - `archived` (boolean, default false) — retirement flag (set only by deferred merge/archive executor).
  - `merged_into_id` (FK nullable, self-ref) — merge pointer (set by deferred executor). Links resolve through this at read time; no text rewriting.
- **`Edge`** — **derived cache**, parse-on-write. Never authored directly.
  - `game_id`, `source_node_id`, `target_node_id`, `verb` (the relationship label from `[verb:: [[Target]]]`; plain `[[Target]]` = generic link).
  - Rebuildable from Node bodies. Enables O(1)-ish backlinks instead of scanning+parsing every Node on read.
- **`NodeVersion`** — snapshot of Node body per change (the *what*).
  - `node_id` (FK), `body` (snapshot), `lock_version` at time of snapshot, `node_action_id` (FK), inserted_at.
- **`NodeAction`** — audit spine (the *who/why*).
  - `game_id`, `node_id` (target FK), `type` — `:create | :update | :merge | :archive`.
  - `source` — `:scribe | :user_ui` (who initiated).
  - Author: `user_id` / `scribe_id` (same two-nullable-FK + CHECK pattern).
  - `triggering_note_id` (FK nullable) — the player Note that caused a Scribe change.
  - `merged_into_id` (FK nullable) — for `:merge`.
  - `reason` (text) — Scribe's "why", or the UI action rationale.
  - inserted_at.

**Audit chain:** player `Note` → `NodeAction` (why/who) → `NodeVersion` (what the text became), with the Scribe's explanatory `Note` (`kind: :scribe`) linked via the action. Full traceability of "why does the wiki say X".

## Per-Game Watermark (idempotency + resume)
Each `Game` tracks `last_processed_note_id` (UUIDv7). This:
- Is the idempotency/dedup key for Scribe jobs (not a wall-clock timestamp — timestamps collide and don't identify the batch).
- Acts as a resume point: a restarted worker continues from the watermark.
- Combined with UUIDv7 time-ordering, defines exactly which Notes a job covers.

## The Scribe Loop (Data Flow)
1. **Input:** A player submits a new `Note` via LiveView.
2. **Persistence:** `Note` saved. LiveView broadcasts it to all clients in that `Game`.
3. **Queueing:** One Oban job enqueued for the Game (concurrency=1 per Game). The **entire job is a single Oban unit** covering both LLM calls below — if either fails, the whole job retries.
4. **Relevance Call (LLM #1):** Fetch unprocessed Notes (those after `last_processed_note_id`). Send them plus the Game's Node list (names, and — pending testing — one-line summaries) to the LLM; receive the set of relevant existing Nodes. (Payload composition to be tuned empirically: names-only may be insufficient to relate "Bob" to "Blacksmith Guild".)
5. **Update Call (LLM #2):** Send the relevant Nodes' bodies + the new Notes; the LLM returns updated text for existing Nodes and/or new Nodes, using embedded syntax for relationships. On potential duplicate, the `(game_id, normalized_name)` unique index triggers **soft-merge** handling (combine into existing; flag as possible duplicate for later human review — no destructive execution in v1).
6. **Persist + Cache:** For each changed Node, in a transaction:
   - Bump `lock_version` (optimistic — stale write aborts the job → retry from watermark).
   - Write `NodeVersion` snapshot + `NodeAction` (source `:scribe`, `triggering_note_id`, `reason`).
   - **Re-parse the Node body and rebuild its `Edge` rows** (parse-on-write cache).
   - Advance `last_processed_note_id`.
7. **Announce:** Insert a `:scribe`-kind `Note` (the "why") into the chat/history. Broadcast Node changes + the scribe Note to the Game's LiveViews (LiveView handles re-render granularity).

### Concurrency & ordering summary
- **Ordering:** guaranteed by per-Game `concurrency: 1`.
- **Correctness under late writes:** guaranteed by `lock_version` optimistic locking.
- **Idempotency/resume:** `last_processed_note_id` watermark.
- **Cancel/coalesce:** explicitly deferred — with concurrency=1, jobs already run one-at-a-time; cancel is only a redundant-work optimization, not a correctness need, and cancellation cannot kill an in-flight LLM HTTP call anyway (the lock covers that case).

## Parsing & UI (Read Path)
When a user views a `Node`, the backend serves clean prose parsed from the body, and a "Known Connections" summary sourced from the **`Edge` cache** (not by re-parsing every Node). Inbound links to merged nodes resolve via `merged_into_id`. Malformed embedded syntax degrades gracefully: the parser drops an unparseable relationship rather than crashing the read path, and the edge-cache rebuild logs the anomaly. No LLM calls on the read path.

## Open Items to Validate Empirically
- Relevance-call payload (names vs names+summaries).
- Prompt strategy for node dedup / "is this the same entity" judgment (backed by the unique-index soft-merge net).
- Scribe behavior when it "can't reconcile" (it will still emit *something*; surfaced in chat for human correction via a new Note).

## Trust Boundary Notes (friends-group v1)
Player Notes are untrusted LLM input; the first audience is a trusted friends group who will also stress-test it. No node deletion is possible except via the (deferred) deterministic UI executor. Prompt-injection hardening is deferred but acknowledged as a real future concern for any wider audience.
