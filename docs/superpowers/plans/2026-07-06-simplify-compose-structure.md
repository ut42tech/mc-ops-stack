# Simplify Compose Structure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure mc-stack so anchors hold only network invariants, each backend declares its own plugin list, and one committed `paper/paper-global.yml` replaces the three-file template machinery.

**Architecture:** Pure config change on a Docker Compose repo (no application code, no test suite). Three edit tasks (compose+env, config-file machinery, docs) each verified with `docker compose config` and grep, plus one runtime verification task on the deployment host. Spec: `docs/superpowers/specs/2026-07-06-simplify-compose-structure-design.md`.

**Tech Stack:** Docker Compose (YAML anchors/merge keys), itzg/minecraft-server images, GNU Make.

## Global Constraints

- **Never weaken the security model**: only the proxy publishes a port; backends stay `ONLINE_MODE=FALSE` on the internal network; forwarding/RCON secrets stay Docker secrets.
- **The `CFG_` prefix is mandatory** in both `CFG_FORWARDING_SECRET_FILE` (compose) and `${CFG_FORWARDING_SECRET}` (paper-global.yml) — substitution is silently skipped otherwise.
- **Images stay pinned** to their current exact tags (`itzg/minecraft-server:2026.7.0-java25`, `itzg/mc-proxy:2025.10.0-java25`, `itzg/mc-backup:2026.6.2`); this plan does not touch them.
- **Verification is `docker compose config`** (also CI) — there are no tests. Run it after every compose.yml edit.
- Work on branch `feat/simplify-compose-structure` (already created; spec committed as 74ed682).
- `.env` is gitignored **site state** — edit it during migration, never commit it.

---

### Task 1: Per-server plugin declarations

**Files:**
- Modify: `compose.yml` (x-paper-env anchor; `lobby`/`survival`/`creative` environment blocks)
- Modify: `.env.example` (replace `PAPER_MODRINTH_PROJECTS` with three variables)
- Modify: `.env` (gitignored live file — migration only, do not commit)

**Interfaces:**
- Produces: env vars `LOBBY_MODRINTH_PROJECTS` (default empty), `SURVIVAL_MODRINTH_PROJECTS` (default empty), `CREATIVE_MODRINTH_PROJECTS` (default `fastasyncworldedit,axiom-paper-plugin`). Task 3's docs must use exactly these names/defaults.

- [ ] **Step 1: Remove `MODRINTH_PROJECTS` from the `x-paper-env` anchor**

In `compose.yml`, replace:

```yaml
  RCON_PASSWORD_FILE: "/run/secrets/rcon_password"

  # Comma-separated Modrinth slugs, resolved against TYPE+VERSION at boot;
  # removing one has itzg delete it. Plugin notes live in .env.example.
  MODRINTH_PROJECTS: "${PAPER_MODRINTH_PROJECTS:-fastasyncworldedit,axiom-paper-plugin}"
```

with:

```yaml
  RCON_PASSWORD_FILE: "/run/secrets/rcon_password"
```

- [ ] **Step 2: Declare plugins in each backend's service block**

In `compose.yml`, `lobby` service — replace:

```yaml
      RCON_CMDS_STARTUP: "${LOBBY_RCON_CMDS_STARTUP:-}"
```

with:

```yaml
      RCON_CMDS_STARTUP: "${LOBBY_RCON_CMDS_STARTUP:-}"
      # Plugins on this backend only — Modrinth slugs; notes live in .env.example.
      MODRINTH_PROJECTS: "${LOBBY_MODRINTH_PROJECTS:-}"
```

`survival` service — replace:

```yaml
      DIFFICULTY: "normal"
```

with:

```yaml
      DIFFICULTY: "normal"
      # Plugins on this backend only — Modrinth slugs; notes live in .env.example.
      MODRINTH_PROJECTS: "${SURVIVAL_MODRINTH_PROJECTS:-}"
```

`creative` service — replace:

```yaml
      RCON_CMDS_STARTUP: "${CREATIVE_RCON_CMDS_STARTUP:-}"
```

with:

```yaml
      RCON_CMDS_STARTUP: "${CREATIVE_RCON_CMDS_STARTUP:-}"
      # Plugins on this backend only — building tools live here, not network-wide.
      MODRINTH_PROJECTS: "${CREATIVE_MODRINTH_PROJECTS:-fastasyncworldedit,axiom-paper-plugin}"
```

- [ ] **Step 3: Replace the plugin variable in `.env.example`**

Replace:

```bash
# Plugins on every Paper backend: comma-separated Modrinth project slugs,
# resolved against TYPE+VERSION at boot. Removing one makes itzg delete it.
# Unset falls back to the compose.yml default (same value as below).
# Notes on the defaults:
# - fastasyncworldedit bundles WorldEdit (needs Java 21+, satisfied by java25).
# - axiom-paper-plugin is only the serverside half: players also need the Axiom
#   CLIENT mod + op/axiom.default perm, and MULTIPLAYER USE REQUIRES a commercial
#   license or a whitelist from the Axiom Discord.
PAPER_MODRINTH_PROJECTS=fastasyncworldedit,axiom-paper-plugin
```

with:

```bash
# Plugins are declared per backend: comma-separated Modrinth project slugs,
# resolved against TYPE+VERSION at boot. Removing one makes itzg delete it.
# Unset falls back to the compose.yml defaults (same values as below).
# Notes on the creative defaults (building tools stay off lobby/survival):
# - fastasyncworldedit bundles WorldEdit (needs Java 21+, satisfied by java25).
# - axiom-paper-plugin is only the serverside half: players also need the Axiom
#   CLIENT mod + op/axiom.default perm, and MULTIPLAYER USE REQUIRES a commercial
#   license or a whitelist from the Axiom Discord.
LOBBY_MODRINTH_PROJECTS=
SURVIVAL_MODRINTH_PROJECTS=
CREATIVE_MODRINTH_PROJECTS=fastasyncworldedit,axiom-paper-plugin
```

- [ ] **Step 4: Migrate the live `.env` (gitignored — edit, don't commit)**

The live `.env` line 28 currently reads:

```bash
PAPER_MODRINTH_PROJECTS=fastasyncworldedit,axiom-paper-plugin,luckperms,essentialsx
```

Replace that single line with (preserves luckperms/essentialsx everywhere; moves the building tools to creative only, per the spec's intent):

```bash
LOBBY_MODRINTH_PROJECTS=luckperms,essentialsx
SURVIVAL_MODRINTH_PROJECTS=luckperms,essentialsx
CREATIVE_MODRINTH_PROJECTS=fastasyncworldedit,axiom-paper-plugin,luckperms,essentialsx
```

- [ ] **Step 5: Verify the rendered config**

Run: `docker compose config | grep MODRINTH_PROJECTS`
Expected: exactly three lines (creative, lobby, survival — compose sorts alphabetically), matching the live `.env` values from Step 4:

```
      MODRINTH_PROJECTS: fastasyncworldedit,axiom-paper-plugin,luckperms,essentialsx
      MODRINTH_PROJECTS: luckperms,essentialsx
      MODRINTH_PROJECTS: luckperms,essentialsx
```

Also run: `docker compose config -q && echo OK`
Expected: `OK`

- [ ] **Step 6: Commit**

```bash
git add compose.yml .env.example
git commit -m "feat: declare plugins per backend instead of network-wide

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: One committed paper-global.yml; remove the template machinery

**Files:**
- Create: `paper/paper-global.yml`
- Modify: `compose.yml` (three volume mounts + header comment)
- Delete: `servers/lobby/config/paper-global.yml.example`, `servers/survival/config/paper-global.yml.example`, `servers/creative/config/paper-global.yml.example`
- Modify: `.gitignore`
- Modify: `Makefile`

**Interfaces:**
- Produces: committed `paper/paper-global.yml`, mounted `:ro` at `/config/paper-global.yml` in every backend. Task 3's docs and Task 4's runtime checks rely on this path.

- [ ] **Step 1: Create `paper/paper-global.yml`**

Content is byte-identical to the current (identical) `servers/*/config/paper-global.yml.example` files:

```yaml
# Minimal paper-global.yml: just the Velocity forwarding block.
# Paper fills every other key with defaults on first boot.
# ${CFG_FORWARDING_SECRET} is substituted at startup from /run/secrets/forwarding_secret.
# itzg's interpolation prefix defaults to "CFG_", so the placeholder here and the
# CFG_FORWARDING_SECRET_FILE env var in compose.yml MUST both be CFG_-prefixed,
# otherwise the substitution is silently skipped and forwarding breaks.
proxies:
  velocity:
    enabled: true
    online-mode: true
    secret: "${CFG_FORWARDING_SECRET}"
```

- [ ] **Step 2: Point all three backends at the shared file**

In `compose.yml`, replace each of these three lines (one per backend):

```yaml
      - ./servers/lobby/config/paper-global.yml:/config/paper-global.yml:ro
```
```yaml
      - ./servers/survival/config/paper-global.yml:/config/paper-global.yml:ro
```
```yaml
      - ./servers/creative/config/paper-global.yml:/config/paper-global.yml:ro
```

each with:

```yaml
      - ./paper/paper-global.yml:/config/paper-global.yml:ro
```

Also update the header comment — replace:

```yaml
#   make setup       # materialize per-server config + .env from *.example templates
```

with:

```yaml
#   make setup       # copy .env from .env.example
```

- [ ] **Step 3: Delete the three template files**

```bash
git rm servers/lobby/config/paper-global.yml.example servers/survival/config/paper-global.yml.example servers/creative/config/paper-global.yml.example
```

- [ ] **Step 4: Remove the stale gitignore rule**

In `.gitignore`, delete this block entirely (the comment is also factually wrong — the secret is substituted inside the container; the `:ro`-mounted host file never holds it):

```
# --- live config materialized from *.example (holds the injected secret) ---
servers/*/config/paper-global.yml

```

- [ ] **Step 5: Shrink `make setup`**

In `Makefile`, replace:

```make
## Materialize per-server live config from committed *.example templates.
setup:
	@for d in servers/*/config; do \
		if [ -f "$$d/paper-global.yml.example" ] && [ ! -f "$$d/paper-global.yml" ]; then \
			cp "$$d/paper-global.yml.example" "$$d/paper-global.yml"; \
			echo "Created $$d/paper-global.yml"; \
		fi; \
	done
	@[ -f .env ] || cp .env.example .env
```

with:

```make
## Materialize .env from the committed .env.example template (kept if it exists).
setup:
	@[ -f .env ] || { cp .env.example .env; echo "Created .env"; }
```

- [ ] **Step 6: Delete the stale gitignored live copies (local disk only)**

```bash
rm -f servers/lobby/config/paper-global.yml servers/survival/config/paper-global.yml servers/creative/config/paper-global.yml
rmdir servers/lobby/config servers/survival/config servers/creative/config
```

Expected: `servers/<name>/` now contains only `data/` and `plugins/` (both gitignored). Nothing mounts these config paths anymore after Step 2.

- [ ] **Step 7: Verify**

Run: `docker compose config | grep -c "paper-global"`
Expected: `3` (all from `paper/paper-global.yml` — confirm with `docker compose config | grep paper-global`, every `source:` is the repo's `paper/paper-global.yml`).

Run: `make setup`
Expected: no output (`.env` exists), exit 0. No `Created servers/...` lines anymore.

Run: `docker compose config -q && echo OK`
Expected: `OK`

- [ ] **Step 8: Commit**

```bash
git add paper/paper-global.yml compose.yml .gitignore Makefile
git commit -m "feat: replace per-server config templates with one committed paper-global.yml

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Documentation sync (README.md, CLAUDE.md; operations.md needs no edits)

**Files:**
- Modify: `README.md` (structure tree, config-flow diagram, quick start, `.env` table, plugins section, add-a-server recipe)
- Modify: `CLAUDE.md` (what-this-is line, commands, template-pattern paragraph, plugins convention, add-a-backend convention)
- Verify-only: `docs/operations.md` (contains no references to the removed machinery)

**Interfaces:**
- Consumes: variable names `LOBBY_/SURVIVAL_/CREATIVE_MODRINTH_PROJECTS` and path `paper/paper-global.yml` exactly as produced by Tasks 1–2.

- [ ] **Step 1: README — repository structure tree**

Replace the `proxy/` and `servers/` parts of the tree:

```
├── proxy/
│   └── velocity.toml      # proxy config template (mounted read-only)
├── secrets/
│   ├── forwarding.secret  # shared HMAC secret       (gitignored; `make secret`)
│   └── rcon.secret        # backends' RCON password  (gitignored; `make secret`)
├── backups/
│   └── <lobby|survival|creative>/  # tar archives from the backup sidecars (gitignored)
└── servers/
    └── <lobby|survival|creative>/
        ├── config/
        │   ├── paper-global.yml.example  # committed template
        │   └── paper-global.yml          # live copy    (gitignored; `make setup`)
        └── data/                         # world, plugins, logs (gitignored)
```

with:

```
├── proxy/
│   └── velocity.toml      # proxy config (mounted read-only)
├── paper/
│   └── paper-global.yml   # shared Paper config (mounted read-only into every backend)
├── secrets/
│   ├── forwarding.secret  # shared HMAC secret       (gitignored; `make secret`)
│   └── rcon.secret        # backends' RCON password  (gitignored; `make secret`)
├── backups/
│   └── <lobby|survival|creative>/  # tar archives from the backup sidecars (gitignored)
└── servers/
    └── <lobby|survival|creative>/
        ├── data/          # world, logs, server jar (gitignored)
        └── plugins/       # plugin jars + their configs (gitignored)
```

- [ ] **Step 2: README — config-flow paragraph + diagram**

Replace (the paragraph AND the fenced diagram that follows it):

````
Config reaches the servers by two routes — templates are copied once, values are
re-read every time a container is (re)created:

```
.env ────(compose ${VAR:-default})────▶ container env ──┐
                                                        ├─(itzg boot: sync + ${CFG_*} expansion)─▶ live config
*.example ──(make setup, copy once)──▶ mounted config ──┘
```
````

with:

````
Config reaches the servers by two routes — committed files are mounted read-only,
values are re-read every time a container is (re)created:

```
.env ──────(compose ${VAR:-default})───▶ container env ──┐
                                                         ├─(itzg boot: sync + ${CFG_*} expansion)─▶ live config
proxy/ + paper/ ──(mounted read-only)──▶ mounted config ──┘
```
````

- [ ] **Step 3: README — quick start**

Replace:

```bash
make setup     # create live config + .env from templates
```

with:

```bash
make setup     # create .env from .env.example
```

- [ ] **Step 4: README — `.env` table row**

Replace:

```
| `PAPER_MODRINTH_PROJECTS`    | `fastasyncworldedit,axiom-paper-plugin` | Plugins on **every backend**: comma-separated Modrinth slugs.            |
```

with:

```
| `LOBBY_MODRINTH_PROJECTS`    | _(empty)_                               | Plugins on **lobby**: comma-separated Modrinth slugs.                    |
| `SURVIVAL_MODRINTH_PROJECTS` | _(empty)_                               | Plugins on **survival**: comma-separated Modrinth slugs.                 |
| `CREATIVE_MODRINTH_PROJECTS` | `fastasyncworldedit,axiom-paper-plugin` | Plugins on **creative**: comma-separated Modrinth slugs.                 |
```

- [ ] **Step 5: README — plugins section table + bullet**

Replace:

```
| Layer         | `.env` variable           | Source              | Defaults                                       |
| ------------- | ------------------------- | ------------------- | ---------------------------------------------- |
| proxy         | `PROXY_SPIGET_PLUGINS`    | Spiget resource IDs | ViaVersion (`19254`), ViaBackwards (`27448`)   |
| every backend | `PAPER_MODRINTH_PROJECTS` | Modrinth slugs      | FastAsyncWorldEdit, Axiom (serverside half)    |
```

with:

```
| Layer      | `.env` variable              | Source              | Defaults                                     |
| ---------- | ---------------------------- | ------------------- | -------------------------------------------- |
| proxy      | `PROXY_SPIGET_PLUGINS`       | Spiget resource IDs | ViaVersion (`19254`), ViaBackwards (`27448`) |
| `lobby`    | `LOBBY_MODRINTH_PROJECTS`    | Modrinth slugs      | _(none)_                                     |
| `survival` | `SURVIVAL_MODRINTH_PROJECTS` | Modrinth slugs      | _(none)_                                     |
| `creative` | `CREATIVE_MODRINTH_PROJECTS` | Modrinth slugs      | FastAsyncWorldEdit, Axiom (serverside half)  |
```

And after the "Via\* lives ONLY on the proxy" bullet, add:

```
- **Each backend declares its own list** — building tools (FAWE, Axiom) default
  to creative only; network-wide plugins are simply listed on every backend.
```

- [ ] **Step 6: README — add-a-server recipe**

Replace:

```
1. Copy a backend block in `compose.yml` (e.g. `survival:`) under a new name,
   with its own `./servers/<name>/data:/data` mount.
2. Create `servers/<name>/config/paper-global.yml.example` (copy an existing
   one) so `make setup` can materialize it; `/data` is created on first run.
3. Add `<name> = "<name>:25565"` under `[servers]` in `proxy/velocity.toml`.
4. `make setup && make up`.
```

with:

```
1. Copy a backend block in `compose.yml` (e.g. `survival:`) under a new name,
   with its own `./servers/<name>/data:/data` and
   `./servers/<name>/plugins:/data/plugins` mounts and its own
   `<NAME>_MODRINTH_PROJECTS` variable. The shared `./paper/paper-global.yml`
   mount is reused as-is; `/data` is created on first run.
2. Add `<name> = "<name>:25565"` under `[servers]` in `proxy/velocity.toml`.
3. `make up`.
```

- [ ] **Step 7: CLAUDE.md — what-this-is, commands, template pattern, conventions**

Replace:

```
the "code" is `compose.yml`, `proxy/velocity.toml`, per-server `paper-global.yml` templates, and the Makefile.
```

with:

```
the "code" is `compose.yml`, `proxy/velocity.toml`, the shared `paper/paper-global.yml`, and the Makefile.
```

Replace:

```bash
make setup     # materialize live config + .env from *.example templates
```

with:

```bash
make setup     # copy .env from .env.example (no-op if .env exists)
```

Replace:

```
Template pattern: committed `*.example` files are copied to gitignored live files by `make setup` (`.env`, `servers/*/config/paper-global.yml`). Edit the `.example`, then re-run `make setup` (it never overwrites existing live files — delete the live file first to regenerate).
```

with:

```
Template pattern: `make setup` copies `.env.example` to a gitignored `.env` (never overwritten — delete `.env` to regenerate). All other config is committed and mounted read-only: `proxy/velocity.toml`, plus one shared `paper/paper-global.yml` mounted into every backend — it holds only the `${CFG_FORWARDING_SECRET}` placeholder, no secret material (substitution happens inside the container). If one server ever needs its own Paper config, point its mount at a dedicated file.
```

Replace (in Conventions):

```
- **Plugins are declared, never committed as jars**: `MODRINTH_PROJECTS` on backends (matched to TYPE+VERSION at boot), `SPIGET_PLUGINS` (resource IDs) on the proxy since mc-proxy can't pull from Modrinth. Removing an entry makes itzg delete that plugin. Both are `.env`-driven (`PAPER_MODRINTH_PROJECTS`, `PROXY_SPIGET_PLUGINS`, comma-separated) with defaults in `compose.yml`.
```

with:

```
- **Plugins are declared, never committed as jars**: `MODRINTH_PROJECTS` per backend (matched to TYPE+VERSION at boot), `SPIGET_PLUGINS` (resource IDs) on the proxy since mc-proxy can't pull from Modrinth. Removing an entry makes itzg delete that plugin. All are `.env`-driven (`LOBBY_`/`SURVIVAL_`/`CREATIVE_MODRINTH_PROJECTS`, `PROXY_SPIGET_PLUGINS`, comma-separated) with defaults in `compose.yml` — building tools (FAWE, Axiom) default to creative only.
```

Replace:

```
- Adding a backend = copy a service block in `compose.yml` with its own `./servers/<name>/data:/data` mount, create `servers/<name>/config/paper-global.yml.example`, register `<name> = "<name>:25565"` under `[servers]` in `proxy/velocity.toml`, then `make setup && make up`.
```

with:

```
- Adding a backend = copy a service block in `compose.yml` with its own `./servers/<name>/data:/data` + `./servers/<name>/plugins:/data/plugins` mounts and `<NAME>_MODRINTH_PROJECTS` variable (the shared `paper/paper-global.yml` mount is reused as-is), register `<name> = "<name>:25565"` under `[servers]` in `proxy/velocity.toml`, then `make up`.
```

- [ ] **Step 8: Verify no stale references remain**

Run: `grep -rn "PAPER_MODRINTH_PROJECTS\|paper-global.yml.example\|servers/\*/config" README.md CLAUDE.md docs/operations.md compose.yml Makefile .gitignore .env.example`
Expected: no matches (exit 1). If anything matches, fix that occurrence the same way as above.

Run: `docker compose config -q && echo OK`
Expected: `OK`

- [ ] **Step 9: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: sync README and CLAUDE.md with per-server plugins and shared paper-global.yml

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Runtime verification (deployment host only — no commit)

**Files:** none (verification only). Skip this task entirely if the stack does not run on this machine; run it on the deployment host after pulling the branch.

**Interfaces:**
- Consumes: the full branch state from Tasks 1–3 and the migrated `.env` from Task 1 Step 4.

- [ ] **Step 1: Recreate the stack**

Run: `docker compose up -d`
Expected: proxy + 3 backends + 3 backup sidecars recreated (env and mounts changed for all backends).

- [ ] **Step 2: Confirm modern forwarding**

Run: `docker compose logs proxy | grep -i forwarding`
Expected: a Velocity boot line confirming player info forwarding is enabled (and no forwarding errors).

- [ ] **Step 3: Confirm the shared file still feeds secret substitution**

Run: `docker compose exec lobby grep secret /data/config/paper-global.yml`
Expected: `secret: "<48-hex-chars>"` — the substituted value, NOT the literal `${CFG_FORWARDING_SECRET}`. A literal placeholder means the `CFG_` wiring broke; stop and fix before proceeding.

- [ ] **Step 4: Confirm per-server plugin sets**

Run: `ls servers/lobby/plugins/*.jar servers/survival/plugins/*.jar servers/creative/plugins/*.jar`
Expected: lobby/survival have LuckPerms + EssentialsX jars only; creative additionally has FastAsyncWorldEdit + Axiom jars. If itzg did not prune the FAWE/Axiom jars from lobby/survival (pruning behavior on shrunken lists can lag), remove them manually and restart those backends:

```bash
rm servers/lobby/plugins/FastAsyncWorldEdit*.jar servers/lobby/plugins/Axiom*.jar
rm servers/survival/plugins/FastAsyncWorldEdit*.jar servers/survival/plugins/Axiom*.jar
docker compose restart lobby survival
```

- [ ] **Step 5: End-to-end join check (manual)**

Connect a Minecraft client to `localhost:25565`, land in lobby, run `/server survival` and `/server creative`. Expected: all three joins succeed (proves forwarding works on every backend with the shared config file).
