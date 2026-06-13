# mc-stack

A small, opinionated **Velocity proxy + Paper backend** Minecraft network,
defined entirely as Docker Compose. Built on the
[itzg](https://github.com/itzg/docker-minecraft-server) images.

```
player ──(25565)──▶ proxy (Velocity) ──internal net──▶ lobby / survival / creative (Paper)
```

| Server     | Gamemode  | Notes                                       |
|------------|-----------|---------------------------------------------|
| `lobby`    | adventure | Superflat, peaceful hub — players land here |
| `survival` | survival  | Normal difficulty                           |
| `creative` | creative  | —                                           |

Backends run Minecraft **26.1.2** on Paper (Java 25); Velocity tracks its latest build.

## Design rules

- **Only the proxy is exposed.** Backends live on an internal Docker network and
  publish no host ports, so an offline-mode backend can never be reached directly.
- **Backends are offline-mode; the proxy authenticates players** (online-mode) and
  hands verified identities to backends via Velocity **modern forwarding**.
- **One shared forwarding secret** (`secrets/forwarding.secret`) HMAC-signs that
  forwarding, so a backend only trusts player info that came from *this* proxy. It is
  the single source of truth — mounted into the proxy and every backend as a Docker
  secret, and never committed.
- **Repo holds config, volumes hold state.** World data lives in named volumes.

## Quick start

```bash
make secret    # generate secrets/forwarding.secret  (run once)
make setup     # create live config + .env from templates
$EDITOR .env   # set OPS (your username) and TZ
make up        # docker compose up -d
```

Connect a Minecraft client to `localhost:25565`. In-game, `/server survival`
switches backends (`/server` is built into Velocity).

## Configuration (`.env`)

| Variable     | Default     | Purpose                                                        |
|--------------|-------------|----------------------------------------------------------------|
| `MC_VERSION` | `26.1.2`    | Minecraft version for all backends. 26.1+ needs the `java25` image tag. |
| `OPS`        | *(empty)*   | Comma-separated operator usernames, applied to every backend.  |
| `TZ`         | `UTC`       | Timezone for log timestamps, e.g. `Asia/Tokyo`.                |

Per-server settings (memory, gamemode, world type) live in `compose.yml`.

## Add a server

1. Copy a backend block in `compose.yml` (see the commented `minigames:` example).
2. Add a matching `minigames_data:` volume, and create
   `servers/minigames/config/paper-global.yml.example` (copy an existing one) plus
   `servers/minigames/plugins/.gitkeep` — without the template, `make setup` skips it
   and Docker mounts a directory where Paper expects a file, breaking the backend.
3. Add `minigames = "minigames:25565"` under `[servers]` in `proxy/velocity.toml`.
4. `make setup && make up`.

## Verifying forwarding

On boot, check `docker compose logs proxy` for modern forwarding and the backend
logs for a clean handshake. If a backend rejects forwarded players, the proxy and
backend secrets don't match — confirm the live `servers/*/config/paper-global.yml`
holds the real secret, not a literal `${CFG_FORWARDING_SECRET}`.
