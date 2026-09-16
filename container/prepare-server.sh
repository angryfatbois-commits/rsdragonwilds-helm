#!/usr/bin/env bash
set -euo pipefail
launcher=${1:-${STEAMAPPDIR:?STEAMAPPDIR required}/RSDragonwildsServer.sh}
original="\"\$UE_PROJECT_ROOT/RSDragonwilds/Binaries/Linux/RSDragonwildsServer-Linux-Shipping\" RSDragonwilds \"\$@\""
patched='env LD_PRELOAD=/opt/rsdwapi/librsdwapi.so '"$original"
invocations=$(sed 's/[[:blank:]]*$//' "$launcher" | grep -E '^(env LD_PRELOAD=[^ ]+ )?".*RSDragonwildsServer-Linux-Shipping' || true)
if [[ $(grep -c 'RSDragonwildsServer-Linux-Shipping' "$launcher" || true) != 2 ]] ||
    ! grep -Fxq "chmod +x \"\$UE_PROJECT_ROOT/RSDragonwilds/Binaries/Linux/RSDragonwildsServer-Linux-Shipping\"" "$launcher" ||
    [[ $invocations != "$original" && $invocations != "$patched" ]]; then
    echo 'Unsupported Dragonwilds launcher: expected one known shipping executable invocation' >&2
    exit 1
fi
if [[ ${RSDWAPI_ENABLED:-true} == false ]]; then
    sed -i 's|^env LD_PRELOAD=/opt/rsdwapi/librsdwapi.so ||' "$launcher"
    exit 0
fi
[[ ${RSDWAPI_ENABLED:-true} == true ]] || { echo 'RSDWAPI_ENABLED must be true or false' >&2; exit 1; }
token=$(< "${RSDWAPI_TOKEN_FILE:?token file required}")
[[ $token =~ ^[A-Za-z0-9._~+/-]+=*$ ]] || { echo 'API token must be a nonempty single-line bearer token' >&2; exit 1; }
port=${RSDWAPI_PORT:-8080}
if [[ ! $port =~ ^[0-9]{1,5}$ ]] || ((10#$port < 1 || 10#$port > 65535)); then
    echo 'Invalid API port' >&2
    exit 1
fi
for flag in "${RSDWAPI_LOGGING:-true}" "${RSDWAPI_VERBOSE:-false}"; do
    [[ $flag == true || $flag == false ]] || { echo 'Logging flags must be true or false' >&2; exit 1; }
done
umask 077
mkdir -p "${RSDWAPI_DIR:?writable API directory required}"
settings=$(mktemp "$RSDWAPI_DIR/.settings.XXXXXX")
trap 'rm -f "$settings"' EXIT
cat > "$settings" <<EOF
[General]
EnableLogging=${RSDWAPI_LOGGING:-true}
VerboseLogging=${RSDWAPI_VERBOSE:-false}
[API]
Enabled=true
BindAddress=127.0.0.1
Port=$port
BearerToken=$token
IPWhitelist=127.0.0.1
[RCON]
Enabled=false
BindAddress=127.0.0.1
Port=27020
Password=
IPWhitelist=127.0.0.1
CommandsPerMinute=60
CommandBurst=15
MaxFailedAuth=5
FailWindowSeconds=60
BanSeconds=300
MaxConnections=16
[Discord]
Enabled=false
WebhookUrl=
Username=Dragonwilds
EOF
mv -f "$settings" "$RSDWAPI_DIR/settings.ini"
if [[ $invocations == "$original" ]]; then
    line_number=$(grep -nF "$original" "$launcher" | cut -d: -f1)
    sed -i "${line_number}s|^|env LD_PRELOAD=/opt/rsdwapi/librsdwapi.so |" "$launcher"
fi
