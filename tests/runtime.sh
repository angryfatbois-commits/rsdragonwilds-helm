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
echo 'Image dependency checks passed.'

container="rsdragonwilds-runtime-${RANDOM}-${RANDOM}"
started=false
cleanup() {
    if [[ "$started" != true ]]; then
        docker logs "$container" 2>&1 | tail -200 || true
    fi
    docker rm -f "$container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --name "$container" --publish 7888:7888/udp \
    --env RSDW_OWNER_ID=0123456789abcdef0123456789abcdef \
    --env RSDW_SERVER_NAME=runtime-smoke \
    --env RSDW_WORLD_NAME=runtime-smoke \
    --env RSDW_PASSWORD= \
    --env RSDW_ADMIN_PASSWORD= \
    --env RSDWAPI_ENABLED=false \
    --env RSDW_PORT=7888 \
    "$image" >/dev/null

for _ in $(seq 1 360); do
    status=$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null || true)
    logs=$(docker logs --tail 100 "$container" 2>&1 || true)
    if grep -Fq 'IpNetDriver listening on port 7888' <<< "$logs"; then
        started=true
        break
    fi
    if [[ "$status" == exited || "$status" == dead ]]; then
        echo "Container exited before binding port 7888" >&2
        exit 1
    fi
    sleep 2
done

if [[ "$started" != true ]]; then
    echo "Container did not bind port 7888 within 12 minutes" >&2
    exit 1
fi
if [[ "$(docker inspect --format '{{.State.Running}}' "$container")" != true ]]; then
    echo "Container is not running after binding port 7888" >&2
    exit 1
fi

echo 'Container startup and custom-port check passed on UDP 7888'
