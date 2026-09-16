#!/usr/bin/env bash
set -euo pipefail
image=${1:-rsdragonwilds-server:dev}
docker run --rm --entrypoint /bin/bash "$image" -ec '
    test -z "${LD_PRELOAD:-}"
    test "$(id -u)" = 1000
    test -r /opt/rsdwapi/librsdwapi.so
    output=$(ldd -r /opt/rsdwapi/librsdwapi.so 2>&1)
    printf "%s\n" "$output"
    ! grep -E "not found|undefined symbol" <<< "$output"
    grep -A1 -x download /entry.sh | grep -Fx /opt/rsdwapi/prepare-server.sh
    /opt/rsdwapi/patch-entrypoint.sh /entry.sh
'
echo 'Image dependency checks passed. Live game/API/save verification is separate; see README.'
