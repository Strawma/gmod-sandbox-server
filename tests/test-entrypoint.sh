#!/usr/bin/env bash
set -Eeuo pipefail

readonly project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly image=${GMOD_IMAGE:-gmod-server:local}
test_dir=$(mktemp -d /tmp/gmod-entrypoint-test.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$test_dir/server/garrysmod/cfg"
install -m 0755 "$project_dir/tests/fake-srcds-run" "$test_dir/server/srcds_run"
# GitHub-hosted runners use a different UID than the image. These disposable
# fixtures must remain writable so the test exercises the image's fixed UID.
chmod 0777 \
  "$test_dir" \
  "$test_dir/server" \
  "$test_dir/server/garrysmod" \
  "$test_dir/server/garrysmod/cfg"

missing_token_output=$(docker run --rm \
  -v "$test_dir:/data" \
  "$image" 2>&1 || true)
[[ $missing_token_output == "ERROR: GSLT is required; create one for Garry's Mod app ID 4000" ]] \
  || fail 'missing GSLT was not rejected'

invalid_collection_output=$(docker run --rm \
  -e GSLT=TESTTOKEN \
  -e WORKSHOP_COLLECTION_ID=not-a-number \
  -v "$test_dir:/data" \
  "$image" 2>&1 || true)
[[ $invalid_collection_output == 'ERROR: WORKSHOP_COLLECTION_ID must be numeric when set' ]] \
  || fail 'invalid Workshop collection was not rejected'

branch_output=$(docker run --rm \
  -e GSLT=TESTTOKEN \
  -e STEAM_BRANCH=prerelease \
  -v "$project_dir/tests/fake-steamcmd:/usr/local/bin/steamcmd:ro" \
  -v "$test_dir:/data" \
  "$image")
[[ $branch_output == *$'[+app_update]\n[4020]\n[-beta]\n[prerelease]'* ]] \
  || fail 'configured Steam branch was not passed to SteamCMD'

launch_output=$(docker run --rm \
  -e GSLT=TESTTOKEN \
  -e UPDATE_ON_START=false \
  -e SERVER_NAME='Test Server' \
  -e SERVER_PASSWORD='two words' \
  -v "$test_dir:/data" \
  "$image")

[[ $launch_output == *$'[+hostname]\n[Test Server]'* ]] \
  || fail 'server name was not preserved as one argument'
[[ $launch_output == *$'[+sv_password]\n[two words]'* ]] \
  || fail 'server password was not preserved as one argument'
[[ -f $test_dir/server/garrysmod/cfg/container-preset.cfg ]] \
  || fail 'preset was not copied into the server configuration'

printf 'Entrypoint tests passed.\n'
