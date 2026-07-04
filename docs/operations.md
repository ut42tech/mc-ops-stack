# Operations

A short runbook for the two things that don't fit in the README: restoring a
backend from backup, and rolling out image/version updates.

## Backups

- One `itzg/mc-backup` sidecar per backend: `backup-lobby`, `backup-survival`,
  `backup-creative`. Each mounts its backend's `/data` **read-only** and
  `./backups/<name>` writable; none of them publish ports.
- Cycle, once per `BACKUP_INTERVAL` (default `24h`): RCON `save-off` → tar
  `/data` into `backups/<name>/` → RCON `save-on`.
- Retention: `PRUNE_BACKUPS_DAYS` (default `7`) — archives older than this are
  deleted automatically. Both knobs live in `.env`.
- mc-backup's own defaults (not overridden here) are `BACKUP_ON_STARTUP=true`
  and `INITIAL_DELAY=2m`, so every `docker compose up` also triggers a backup
  about 2 minutes after boot, in addition to the interval.
- On-demand backup, e.g. right before a risky change:

  ```bash
  docker compose exec backup-lobby backup now
  ```

  (swap `backup-lobby` for `backup-survival` / `backup-creative`.) Runs
  immediately with the same save-off/tar/save-on flow, without waiting for
  `BACKUP_INTERVAL`.

## Restore procedure

Archives land in `backups/<name>/` as gzip-compressed tars named
`world-<YYYYMMDD-HHMMSS>.tar.gz` (mc-backup's defaults: `BACKUP_NAME=world`,
`TAR_COMPRESS_METHOD=gzip`). To restore backend `<name>` from one:

1. Stop the stack:

   ```bash
   docker compose down
   ```

2. Find the archive to restore — e.g. the newest one:

   ```bash
   ls -t backups/<name>/*.tar.gz | head -1
   ```

3. Move the broken data directory aside and create a fresh one:

   ```bash
   mv servers/<name>/data servers/<name>/data.bak
   mkdir -p servers/<name>/data
   ```

4. Extract the chosen archive into it:

   ```bash
   tar xzf backups/<name>/<archive>.tar.gz -C servers/<name>/data
   ```

5. Bring the stack back up and verify:

   ```bash
   make up
   docker compose logs -f <name>
   ```

   Confirm the world loads and the right players/plugins/data are present,
   then delete `servers/<name>/data.bak` once you're satisfied.

## Update runbook

- **Routine image bumps**: [Dependabot](../.github/dependabot.yml) opens
  weekly PRs bumping pinned image tags (proxy, backends, backup sidecars) and
  GitHub Actions. CI ([`.github/workflows/validate.yml`](../.github/workflows/validate.yml))
  runs `make secret setup` then `docker compose config -q` on every PR and on
  push to `main`. Once CI is green and the PR is merged:

  ```bash
  docker compose pull
  docker compose up -d
  ```

- **`MC_VERSION` bump** (the actual Minecraft version) is manual — Dependabot
  only tracks image tags, not the game version string:

  1. Edit `MC_VERSION` in both `.env` (so your site picks it up) and
     `.env.example` (so the committed default stays current for new sites).
  2. Check the Java requirement for the new version. If it changes, update the
     backend image's `-javaNN` variant in `compose.yml`
     (`x-paper-common.image`) to match — 26.1+ requires a `*-java25` tag; only
     drop to `*-java21` when pinning a 1.21.x version.
  3. `docker compose up -d` to recreate the backends on the new version.
