#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
reject() { if "$@" >"$work/rejected.log" 2>&1; then fail "unexpected success: $*"; fi; }
for script in container/*.sh tests/*.sh; do bash -n "$script"; done
if command -v shellcheck >/dev/null; then shellcheck container/*.sh tests/*.sh; fi
cp tests/fixtures/entry.sh "$work/entry"
bash container/patch-entrypoint.sh "$work/entry"
grep -Fxq "    -Port=\"\${RSDW_PORT}\"" "$work/entry"
cp "$work/entry" "$work/entry.once"
bash container/patch-entrypoint.sh "$work/entry"
cmp "$work/entry" "$work/entry.once"
printf '\ndownload\n' >> "$work/entry"
reject bash container/patch-entrypoint.sh "$work/entry"
cp tests/fixtures/RSDragonwildsServer.sh "$work/launcher"
printf 'test-token' > "$work/token"
export RSDWAPI_DIR="$work/api" RSDWAPI_TOKEN_FILE="$work/token"
bash container/prepare-server.sh "$work/launcher"
cp "$work/launcher" "$work/launcher.once"
bash container/prepare-server.sh "$work/launcher"
cmp "$work/launcher" "$work/launcher.once"
grep -Fxq 'BearerToken=test-token' "$work/api/settings.ini"
grep -Fxq 'BindAddress=127.0.0.1' "$work/api/settings.ini"
[[ $(grep -c LD_PRELOAD "$work/launcher") == 1 ]] || fail 'preload must appear once'
RSDWAPI_ENABLED=false bash container/prepare-server.sh "$work/launcher"
cmp tests/fixtures/RSDragonwildsServer.sh "$work/launcher"
printf '\nunknown-shipping-invocation\n' > "$work/unknown"
reject bash container/prepare-server.sh "$work/unknown"
cat tests/fixtures/RSDragonwildsServer.sh tests/fixtures/RSDragonwildsServer.sh > "$work/duplicate"
reject bash container/prepare-server.sh "$work/duplicate"
printf 'bad\ntoken' > "$work/token"
reject bash container/prepare-server.sh "$work/launcher"
mkdir "$work/source" "$work/destination"
printf 'original-world' > "$work/source/world.sav"
bash container/seed-save.sh "$work/source" world.sav "$work/destination"
printf 'progress' > "$work/destination/world.sav"
bash container/seed-save.sh "$work/source" world.sav "$work/destination"
[[ $(< "$work/destination/world.sav") == progress ]] || fail 'import overwrote progress'
reject bash container/seed-save.sh "$work/source" ../world.sav "$work/other"
reject bash container/seed-save.sh "$work/source" /world.sav "$work/other"
printf 'outside' > "$work/outside.sav"
ln -s "$work/outside.sav" "$work/source/escape.sav"
reject bash container/seed-save.sh "$work/source" escape.sav "$work/other"
mkdir "$work/interrupted"
printf 'partial' > "$work/interrupted/.seed.interrupted"
bash container/seed-save.sh "$work/source" world.sav "$work/interrupted"
cmp "$work/source/world.sav" "$work/interrupted/world.sav"
echo 'Container hook and save import checks passed'
python3 tests/chart.py
