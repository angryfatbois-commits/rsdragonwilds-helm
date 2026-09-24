#!/usr/bin/env bash
set -euo pipefail

version=${1:?release version is required}
image=ghcr.io/angryfatbois-commits/rsdragonwilds-server
chart=charts/rsdragonwilds
package_dir=dist

case "$version" in
  ''|*[!0-9.]*|.*|*.)
    printf 'invalid release version: %s\n' "$version" >&2
    exit 2
    ;;
esac

docker buildx build \
  --platform linux/amd64 \
  --push \
  --tag "$image:$version" \
  --cache-from type=gha \
  --cache-to type=gha,mode=max \
  .

mkdir -p "$package_dir"
helm package "$chart" --destination "$package_dir"
helm push "$package_dir/rsdragonwilds-$version.tgz" oci://ghcr.io/angryfatbois-commits/charts
