# On-demand Garry's Mod server

This project runs a private Garry's Mod dedicated server in Docker. The initial
preset is vanilla Sandbox on `gm_construct`. The image installs or updates the
server through SteamCMD when the container starts, then runs it as UID and GID
1000.

## Persistent data

Create the host directory before the first launch:

```bash
sudo install -d -o 1000 -g 1000 /home/ramis/docker/gmod
```

The directory contains the server installation, configuration copied at
startup, saves, logs, addons, and Steam Workshop cache. Back up game and addon
state that cannot be recreated. The base installation and Workshop cache can
be excluded from backups when storage space matters.

Do not run two preset containers against this directory at the same time.
SteamCMD and GMod both write to the shared installation.

## First launch

Create a token in [Steam's game-server account
management](https://steamcommunity.com/dev/managegameservers) for Garry's Mod
application ID `4000`. Application `4020` is the dedicated-server download and
is not the value used when creating the token.

Keep secrets blank in the repository. Before creating the service, populate
these environment values through Cosmos:

- `GSLT`: the game-server login token
- `SERVER_PASSWORD`: a join password, strongly recommended before exposing the
  server to the internet

Start `gmod-sandbox`. The first launch downloads several gigabytes and can take
a while. Later launches check for updates but reuse the persistent installation.
Set `VALIDATE_ON_START=true` temporarily if an interrupted update or damaged
installation needs a full verification.

## Published image and automatic updates

GitHub Actions publishes `ghcr.io/strawma/gmod-sandbox-server:latest` whenever
container code or presets change on `main`. It also rebuilds at 05:15 UTC every
Sunday to pick up changes from the rolling SteamCMD base and Ubuntu packages.
Every image also receives an immutable `sha-<commit>` tag for rollback.

The workflow publishes with GitHub's repository-scoped token, so no registry
write credential needs to be added as a repository secret. A package associated
with a private repository is private by default. Configure a GitHub personal
access token (classic) with only `read:packages` in Cosmos's registry
credentials, using the GitHub username as the registry username. If the package
is deliberately made public later, Cosmos can pull it anonymously.

Enable automatic updates for the container in Cosmos after the first successful
deployment. An image update recreates the container and interrupts an active
game session, while `/home/ramis/docker/gmod` remains untouched. The Compose
`pull_policy: always` also fetches the current image whenever the service is
recreated manually.

The container publishes UDP port 27015. LAN players can connect to
`192.168.50.49:27015`. Internet players need UDP 27015 forwarded by the router
to `192.168.50.49`. The router rule may remain in place: Docker removes its
listener while the container is stopped. TCP 27015 is intentionally not
published, so RCON is not reachable from outside the container.

## Workshop collections and additional presets

Vanilla Sandbox leaves `WORKSHOP_COLLECTION_ID` empty. For a modded mode:

1. Add a public or unlisted Steam Workshop collection.
2. Add `presets/<name>.cfg` for mode-specific server settings and allow the
   publishing workflow to build the updated image.
3. Copy the service and give it a unique service and container name.
4. Change `PRESET`, `GAMEMODE`, `START_MAP`, `SERVER_NAME`, and
   `WORKSHOP_COLLECTION_ID`.
5. Keep the same `/home/ramis/docker/gmod:/data` mount and UDP 27015 mapping.

The common data mount lets every preset reuse installed server files and cached
Workshop content. The shared UDP mapping also prevents two presets from binding
successfully at once, but stop the active preset before starting another rather
than relying on the port conflict.

Workshop content is checked on startup. Updates can change addon behavior, and
removed collection items may remain in the cache until they are cleaned up
manually.

## Updates and rollback

`UPDATE_ON_START=true` checks application 4020 before every launch. This keeps
an on-demand server compatible with current clients but means upstream game
updates are applied when a session starts. Preserve backups of irreplaceable
state and avoid starting immediately before a session when a controlled update
window is important.

Rebuilding the image refreshes the SteamCMD base and operating-system packages.
The GMod installation itself remains under `/home/ramis/docker/gmod`.

## Validation

After building `gmod-server:local`, run the entrypoint behavior checks with:

```bash
./tests/test-entrypoint.sh
```

The tests use a temporary fake server executable and do not download GMod.
