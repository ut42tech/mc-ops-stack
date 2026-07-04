# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Minecraft server network (Velocity proxy + Paper backends) defined entirely as Docker Compose on [itzg](https://github.com/itzg/docker-minecraft-server) images. There is no application code, build step, or test suite — the "code" is `compose.yml`, `proxy/velocity.toml`, per-server `paper-global.yml` templates, and the Makefile.

## Commands

```bash
make secret    # generate secrets/{forwarding,rcon}.secret (once; no-op for any that already exist)
make setup     # materialize live config + .env from *.example templates
make up        # docker compose up -d
make down / restart / ps / logs
```

Verification (no tests exist — this is how changes are checked):

- `docker compose config` — validate compose YAML / anchor merging before `make up`; the same command runs in CI (`.github/workflows/validate.yml`, job `compose-config`) after `make secret setup`, on every push to `main` and every PR
- `docker compose logs proxy` — confirm modern forwarding on boot
- `docker compose exec lobby grep secret /data/config/paper-global.yml` — inspect the secret Paper actually loaded when forwarding fails

## Architecture

```
player ──(25565)──▶ proxy (Velocity) ──internal `mc` net──▶ lobby / survival / creative (Paper)
```

Security model (do not weaken any leg of it):

- **Only the proxy publishes a host port.** Backends run `ONLINE_MODE=FALSE` and are reachable only on the internal network — exposing a backend port would let anyone join with a spoofed username.
- The proxy authenticates players (online-mode) and passes identity via **Velocity modern forwarding**, HMAC-signed with the shared secret `secrets/forwarding.secret`, mounted as a Docker secret into the proxy and every backend.
- A second secret, `secrets/rcon.secret`, is the backends' shared RCON password (`RCON_PASSWORD_FILE` → the `rcon_password` Docker secret). RCON publishes no port and stays internal-network-only; its only consumer besides Paper itself is the backup sidecars pausing/resuming saves.

How the secret reaches Paper — the `CFG_` gotcha: itzg substitutes `${CFG_*}` placeholders while syncing `/config` into `/data` (or `/server` on the proxy). The interpolation prefix defaults to `CFG_`, so the env var in `compose.yml` (`CFG_FORWARDING_SECRET_FILE`) and the placeholder in `paper-global.yml` (`${CFG_FORWARDING_SECRET}`) must both keep that prefix — otherwise substitution is **silently skipped** and forwarding breaks. Same mechanism drives `CFG_MOTD` in `velocity.toml`.

Config layering in `compose.yml`: backends share the `x-paper-common` / `&paper-env` YAML anchors; per-service blocks override with `<<: [*paper-env, *flat-world]`-style merges. Edit the anchor for network-wide changes, the service block for one server.

Template pattern: committed `*.example` files are copied to gitignored live files by `make setup` (`.env`, `servers/*/config/paper-global.yml`). Edit the `.example`, then re-run `make setup` (it never overwrites existing live files — delete the live file first to regenerate). Runtime state (`servers/*/data/`, `compose.override.yml`) is gitignored; a local `compose.override.yml` may exist to trim memory for testing and is auto-merged by compose.

Backups: one `itzg/mc-backup` sidecar per backend (`backup-lobby`/`backup-survival`/`backup-creative`), sharing the `x-backup-common`/`x-backup-env` anchors. Each mounts its backend's `/data` **read-only** (`:ro`) plus `./backups/<name>` writable, publishes no ports, and runs RCON `save-off` → tar → `save-on` on a loop. Interval and retention are `.env`-driven (`BACKUP_INTERVAL` default `24h`, `PRUNE_BACKUPS_DAYS` default `7`); archives are gitignored under `/backups/`.

## Conventions

- **Plugins are declared, never committed as jars**: `MODRINTH_PROJECTS` on backends (matched to TYPE+VERSION at boot), `SPIGET_PLUGINS` (resource IDs) on the proxy since mc-proxy can't pull from Modrinth. Removing an entry makes itzg delete that plugin. Both are `.env`-driven (`PAPER_MODRINTH_PROJECTS`, `PROXY_SPIGET_PLUGINS`, comma-separated) with defaults in `compose.yml`.
- **RCON startup commands live in `.env`** (`LOBBY_RCON_CMDS_STARTUP`, `CREATIVE_RCON_CMDS_STARTUP`, newline-delimited inside double quotes) — compose `${VAR:-default}` interpolation rejects multi-line defaults, so they can't fall back in `compose.yml`. Command failures are non-fatal and only visible via `docker compose logs <backend> | grep "Rcon loop"`. Since MC 1.21.11 (26.x) gamerules use snake_case registry names (`spawn_mobs`, `advance_time`, `advance_weather`); old camelCase names fail with "Incorrect argument for command".
- **Via\* (protocol translation) lives ONLY on the proxy.** Adding it to a backend too breaks joins with version mismatches.
- **Version coupling**: `MC_VERSION` (in `.env`, e.g. `26.1.2`) and the backend image's Java variant move together — MC 26.1+ requires a `*-java25` tag; only drop to `*-java21` when pinning a 1.21.x version. Pin `MC_VERSION` to a stable release rather than `LATEST`.
- **Image pinning + Dependabot**: every image (proxy, backends, backup sidecars) is pinned to a specific verified release, e.g. `itzg/minecraft-server:2026.7.0-java25`, `itzg/mc-proxy:2025.10.0-java25`, `itzg/mc-backup:2026.6.2`, plus `VELOCITY_VERSION: "3.5.0-SNAPSHOT"` (the finest pin itzg exposes — the build within that version string still floats). Never pin to `latest`. Dependabot (`.github/dependabot.yml`, `docker-compose` + `github-actions` ecosystems) opens weekly PRs to bump these; `MC_VERSION` itself is a separate, manual, coupled bump (see the version-coupling bullet above) since Dependabot only tracks image tags, not the Minecraft version string.
- **KISS**: minimal correct config only — Paper fills unspecified keys with defaults, so `paper-global.yml` holds just the forwarding block. Don't add preemptive tuning. Personal/site values (OPS, TZ, PROXY_MOTD) go through `.env`, not hardcoded in compose.
- Adding a backend = copy a service block in `compose.yml` with its own `./servers/<name>/data:/data` mount, create `servers/<name>/config/paper-global.yml.example`, register `<name> = "<name>:25565"` under `[servers]` in `proxy/velocity.toml`, then `make setup && make up`.
