# Simplify compose structure: invariants-only anchors, per-server plugins, one shared paper-global.yml

**Date:** 2026-07-06
**Status:** Design approved; implementation pending

## Goal

Optimize the stack for its two stated priorities — simple to write, easy to understand — without weakening the security model. Guiding principle:

> Anchors hold only what must never differ between servers. A service block is the complete description of that server's personality. Everything except secrets and runtime data is committed.

After this change the orientation story for a new (student) admin is two sentences: "To understand a server, read its service block. The two `x-paper-*` anchors are network invariants — don't touch them."

## Changes

### 1. compose.yml — invariants-only anchors, per-server plugin lists

- Remove `MODRINTH_PROJECTS` from `x-paper-env`. The anchor then holds only settings that are network-wide by intent: `EULA`, `TYPE`, `VERSION`, `USE_AIKAR_FLAGS`, `TZ`, `OPS`, `ONLINE_MODE=FALSE`, the forwarding-secret wiring (`CFG_FORWARDING_SECRET_FILE`, `REPLACE_ENV_*`), and the RCON password wiring.
- Each backend declares its own plugin list in its service block:
  - `lobby`: `MODRINTH_PROJECTS: "${LOBBY_MODRINTH_PROJECTS:-}"` (default: none)
  - `survival`: `MODRINTH_PROJECTS: "${SURVIVAL_MODRINTH_PROJECTS:-}"` (default: none)
  - `creative`: `MODRINTH_PROJECTS: "${CREATIVE_MODRINTH_PROJECTS:-fastasyncworldedit,axiom-paper-plugin}"`
- All three backends mount the same committed config file: `./paper/paper-global.yml:/config/paper-global.yml:ro` (replaces the per-server `./servers/<name>/config/paper-global.yml` mounts).
- Everything else in compose.yml is unchanged: topology, Docker secrets, backup sidecars, log rotation, and the `x-paper-common` / `x-backup-*` / `x-flat-world` / `x-logging` anchors.

Intent behind the defaults: FAWE and Axiom are building tools and belong on creative only. This is a deliberate behavior change from today's network-wide default (see Migration).

### 2. paper/paper-global.yml — one committed shared file

- New committed file `paper/paper-global.yml` (directory chosen to mirror `proxy/velocity.toml`), byte-identical to today's three `servers/*/config/paper-global.yml.example` files (which are themselves identical), including the `CFG_` prefix warning comments.
- It contains only the `${CFG_FORWARDING_SECRET}` placeholder — no secret material. itzg substitutes the secret inside the container while syncing `/config` into `/data`; the host file is mounted `:ro` and never modified.
- Delete `servers/{lobby,survival,creative}/config/paper-global.yml.example` (3 files). `servers/*/config/` disappears from git entirely.
- Escape hatch: if one server ever needs different Paper global config, give it its own file and point that server's mount at it (a 2-line change).

### 3. Makefile

`make setup` shrinks to `.env` materialization only (`[ -f .env ] || cp .env.example .env`). `secret`, `up`, `down`, `restart`, `ps`, `logs` are unchanged.

### 4. .gitignore

Remove the `servers/*/config/paper-global.yml` rule and its comment. (The comment claims the live file "holds the injected secret", which is not true — substitution happens inside the container, never on the host file.)

### 5. .env.example

Replace `PAPER_MODRINTH_PROJECTS` with three per-server variables whose values match the compose.yml defaults:

```bash
LOBBY_MODRINTH_PROJECTS=
SURVIVAL_MODRINTH_PROJECTS=
CREATIVE_MODRINTH_PROJECTS=fastasyncworldedit,axiom-paper-plugin
```

Keep the Axiom licensing note attached to the creative line. All other variables and the file's style are unchanged.

### 6. Documentation (README.md, CLAUDE.md, docs/operations.md)

- The template-pattern description shrinks to `.env` only; remove the "delete the live file to regenerate" caveat for paper-global.yml.
- Plugin convention becomes per-server declaration. Via* stays proxy-only (unchanged).
- Adding a backend loses a step: copy a service block (it mounts the shared `paper/paper-global.yml` as-is), register the server in `proxy/velocity.toml` `[servers]`, `make up`.

## Explicitly out of scope / unchanged

- Topology, security model, Docker secrets, backup sidecars, log rotation, CI workflow (`validate.yml` passes unchanged), image pinning / Dependabot story, general `.env.example` style.
- Plugin selection beyond preserving today's two defaults on creative. (LuckPerms / CoreProtect adoption is a separate future decision.)

## Migration (existing running install)

1. If the live `.env` sets `PAPER_MODRINTH_PROJECTS`, hand-split it into the three new variables. One-time manual edit; no automation.
2. On the next `docker compose up -d`, lobby and survival lose the FAWE/Axiom jars — this is the intended behavior change. If itzg does not prune on an empty list, delete the jars manually from `./servers/<name>/plugins/` (host-visible).
3. Stale gitignored `servers/*/config/paper-global.yml` live copies can be deleted.

## Verification (no test suite; per repo convention)

1. `docker compose config` validates (also runs in CI).
2. `make up` → `docker compose logs proxy` shows modern forwarding on boot.
3. `docker compose exec lobby grep secret /data/config/paper-global.yml` shows the substituted secret — proves the shared `:ro` mount still feeds substitution.
4. Each `servers/<name>/plugins/` matches its declared list.

## Net effect

Removed: 3 identical template files, the Makefile copy loop, one gitignore rule (and its false comment), the "delete live file to regenerate" operational caveat, and one step from the add-a-backend recipe. Added: two `.env` variables (1 → 3).
