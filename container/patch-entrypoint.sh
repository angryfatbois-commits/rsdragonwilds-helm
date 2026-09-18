#!/usr/bin/env bash
set -euo pipefail
entry=${1:?entrypoint path required}
hook='/opt/rsdwapi/prepare-server.sh'
[[ $(grep -xc download "$entry" || true) == 1 ]] || { echo 'Unsupported Jagex entrypoint: expected one download call' >&2; exit 1; }
if [[ $(grep -Fxc "$hook" "$entry" || true) == 1 ]] && grep -A1 -x download "$entry" | grep -Fxq "$hook"; then
    exit 0
fi
! grep -Fq "$hook" "$entry" || {
    echo 'Unsupported Jagex entrypoint: expected one download call without a hook' >&2
    exit 1
}
sed -i -e '\|^download$|a /opt/rsdwapi/prepare-server.sh' -e "s/-Port \"\${RSDW_PORT}\"/-Port=\"\${RSDW_PORT}\"/" "$entry"
