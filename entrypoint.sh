#!/usr/bin/env bash
set -Eeuo pipefail

readonly server_dir=/data/server
readonly preset_dir=/presets
readonly app_id=4020

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_name() {
  local label=$1
  local value=$2

  [[ $value =~ ^[A-Za-z0-9_-]+$ ]] || fail "$label may contain only letters, numbers, underscores, and hyphens"
}

require_integer() {
  local label=$1
  local value=$2
  local minimum=$3
  local maximum=$4

  [[ $value =~ ^[0-9]+$ ]] || fail "$label must be an integer"
  ((value >= minimum && value <= maximum)) || fail "$label must be between $minimum and $maximum"
}

require_boolean() {
  local label=$1
  local value=$2

  [[ $value == true || $value == false ]] || fail "$label must be true or false"
}

update_server() {
  local attempt
  local -a update_args=(+app_update "$app_id")

  if [[ $VALIDATE_ON_START == true ]]; then
    update_args+=(validate)
  fi

  # Steam's content servers occasionally fail transiently. A bounded retry is
  # quicker to recover than waiting for Docker's container restart backoff.
  for attempt in 1 2 3; do
    printf 'Installing or updating Garry\x27s Mod server (attempt %s of 3)...\n' "$attempt"
    if steamcmd \
      +force_install_dir "$server_dir" \
      +login anonymous \
      "${update_args[@]}" \
      +quit; then
      return
    fi

    if ((attempt < 3)); then
      sleep $((attempt * 5))
    fi
  done

  fail "SteamCMD could not install or update Garry's Mod after three attempts"
}

PRESET=${PRESET:-sandbox}
GAMEMODE=${GAMEMODE:-sandbox}
START_MAP=${START_MAP:-gm_construct}
MAX_PLAYERS=${MAX_PLAYERS:-16}
SERVER_PORT=${SERVER_PORT:-27015}
SERVER_NAME=${SERVER_NAME:-Ramis GMod Sandbox}
SERVER_PASSWORD=${SERVER_PASSWORD:-}
GSLT=${GSLT:-}
WORKSHOP_COLLECTION_ID=${WORKSHOP_COLLECTION_ID:-}
UPDATE_ON_START=${UPDATE_ON_START:-true}
VALIDATE_ON_START=${VALIDATE_ON_START:-false}

require_name PRESET "$PRESET"
require_name GAMEMODE "$GAMEMODE"
require_name START_MAP "$START_MAP"
require_integer MAX_PLAYERS "$MAX_PLAYERS" 1 128
require_integer SERVER_PORT "$SERVER_PORT" 1024 65535
require_boolean UPDATE_ON_START "$UPDATE_ON_START"
require_boolean VALIDATE_ON_START "$VALIDATE_ON_START"
[[ -n $GSLT ]] || fail "GSLT is required; create one for Garry's Mod app ID 4000"
[[ $GSLT =~ ^[A-Za-z0-9]+$ ]] || fail 'GSLT must contain only letters and numbers'
if [[ -n $WORKSHOP_COLLECTION_ID && ! $WORKSHOP_COLLECTION_ID =~ ^[0-9]+$ ]]; then
  fail 'WORKSHOP_COLLECTION_ID must be numeric when set'
fi
[[ -f "$preset_dir/$PRESET.cfg" ]] || fail "preset not found: $preset_dir/$PRESET.cfg"
[[ -d /data && -w /data ]] || fail '/data must be writable by UID and GID 1000'

mkdir -p "$server_dir"
if [[ $UPDATE_ON_START == true || ! -x $server_dir/srcds_run ]]; then
  update_server
fi
[[ -x $server_dir/srcds_run ]] || fail 'GMod is not installed; enable UPDATE_ON_START'

# Source looks here for Steam's 32-bit client library. SteamCMD updates the
# source file, so the symlink continues to follow future client releases.
mkdir -p "$HOME/.steam/sdk32"
ln -sfn \
  "$HOME/.local/share/Steam/steamcmd/linux32/steamclient.so" \
  "$HOME/.steam/sdk32/steamclient.so"

install -m 0644 \
  "$preset_dir/$PRESET.cfg" \
  "$server_dir/garrysmod/cfg/container-preset.cfg"

server_args=(
  -game garrysmod
  -console
  -usercon
  -norestart
  -strictportbind
  -ip 0.0.0.0
  -port "$SERVER_PORT"
  +clientport 27005
  +maxplayers "$MAX_PLAYERS"
  +gamemode "$GAMEMODE"
  +map "$START_MAP"
  +exec container-preset.cfg
  +sv_setsteamaccount "$GSLT"
  +hostname "$SERVER_NAME"
)

if [[ -n $SERVER_PASSWORD ]]; then
  server_args+=(+sv_password "$SERVER_PASSWORD")
else
  printf 'WARNING: SERVER_PASSWORD is empty; anyone who can reach the server may join.\n' >&2
fi

if [[ -n $WORKSHOP_COLLECTION_ID ]]; then
  server_args+=(+host_workshop_collection "$WORKSHOP_COLLECTION_ID")
fi

printf 'Starting preset %s: gamemode=%s map=%s port=%s\n' \
  "$PRESET" "$GAMEMODE" "$START_MAP" "$SERVER_PORT"
exec "$server_dir/srcds_run" "${server_args[@]}"
