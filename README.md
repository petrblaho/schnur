# Schnur

Collaborative note-taking for tabletop RPG campaigns, with an LLM "Scribe"
that weaves raw, timestamped notes into a structured, interconnected wiki
(characters, places, items, events).

See [docs/superpowers/specs/2026-08-21-schnur-core-architecture-design.md](docs/superpowers/specs/2026-08-21-schnur-core-architecture-design.md)
for the core architecture and Scribe design.

## Prerequisites

* Elixir 1.20.3 / OTP 29 — pinned via [mise](https://mise.jdx.dev/); run `mise install`
* PostgreSQL. Start the bundled database with:

      podman-compose up -d      # or: docker compose up -d

  This runs PostgreSQL 17 on host port **5433** (matching the dev/test
  config in `config/`). The port differs from the default 5432 to avoid
  clashing with other local PostgreSQL instances.

## Running

* `mix setup` — install dependencies, create and migrate the database, and build assets
* `mix phx.server` (or `iex -S mix phx.server`) — start the Phoenix endpoint

Now you can visit [`localhost:4001`](http://localhost:4001) from your browser.
The dev port defaults to **4001** (override with the `PORT` env var); 4000 is
intentionally avoided as it is used by the local LiteLLM proxy.

Ready to run in production? Please [check the deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
