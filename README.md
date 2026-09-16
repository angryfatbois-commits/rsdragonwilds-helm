# rsdragonwilds-helm

Run one RuneScape Dragonwilds dedicated server per Helm release. The image extends Jagex's official `1.1.1` container and builds RSDWServerAPI `0.1.3` from pinned source against Steam Runtime Sniper. The chart persists the game, world saves, and mod state. An optional JSON exporter `v0.8.0` supplies Prometheus metrics.

This is an unofficial community project. Game updates arrive through SteamCMD at startup, independently of the pinned container and mod versions.

## Install a server

Use an amd64 Kubernetes node, a storage class or existing PVC, and a UDP load balancer. Choose CPU, memory, and disk capacity for your server. The default PVC requests 40Gi. Helm 3 or 4 supports the OCI chart.

Create a namespace and a persistent bearer-token Secret. Helm never generates or replaces this token.

```sh
kubectl create namespace dragonwilds
kubectl -n dragonwilds create secret generic rsdw-api \
  --from-literal=token="$(openssl rand -hex 32)"
```

Create `my-values.yaml`. Find your EOS player ID in the game's settings.

```yaml
server:
  env:
    RSDW_OWNER_ID: YOUR_EOS_PLAYER_ID
    RSDW_SERVER_NAME: My server
    RSDW_WORLD_NAME: My world
api:
  bearerTokenSecret:
    name: rsdw-api
```

After the first public release is available, install it.

```sh
helm upgrade --install game oci://ghcr.io/petzkod5/charts/rsdragonwilds \
  --version 0.1.0 --namespace dragonwilds -f my-values.yaml
kubectl -n dragonwilds logs -f deployment/game-rsdragonwilds -c server
kubectl -n dragonwilds get service game-rsdragonwilds
```

For a checkout before publication, substitute `./charts/rsdragonwilds` for the OCI URL and omit `--version`. Set `image.repository` and `image.tag` to an image available to your cluster.

Steam downloads the game before startup. Readiness waits for the API's `engineReady` flag and does not restart a slow download. Use the Service's external numeric IP and UDP port to connect. Public server discovery depends on the game and EOS services.

With no imported save, the game generates a world. Saves live at `/home/steam/rsdw-dedicated/RSDragonwilds/Saved/SaveGames`, with a capital `G` in `Games`.

## Configure the server

[values.yaml](charts/rsdragonwilds/values.yaml) lists every setting and default. The schema rejects unknown chart keys and invalid port types. Use quoted strings in `server.env`.

| Values | Effect |
| --- | --- |
| `image.repository`, `tag`, `digest`, `pullPolicy` | Select the server image. Digest overrides tag. An empty tag uses `Chart.appVersion`. |
| `server.port` | Set the game container port and `RSDW_PORT`. |
| `server.env`, `server.extraEnv` | Upstream environment map and Kubernetes EnvVar overrides. An override replaces the same map key once. |
| `config.dedicatedServerIni` | Complete optional INI template. Empty uses the upstream template. |
| `persistence.existingClaim`, `size`, `storageClass`, `accessModes`, `retain` | Existing or chart-created data volume. `null` storage class uses the cluster default; `""` requests no class. |
| `saveSeed.existingClaim`, `path` | Initial import from a separate read-only PVC. |
| `api.enabled`, `port`, `bearerTokenSecret.name`, `bearerTokenSecret.key` | Localhost REST listener and existing token Secret. |
| `api.logging.enabled`, `api.logging.verbose` | Mod logging flags. |
| `metrics.enabled`, `metrics.image`, `metrics.resources` | Optional exporter container, pinned version, and resources. Requires API. |
| `metrics.serviceMonitor.enabled`, `interval`, `labels` | Prometheus Operator discovery. The CRD must already exist. |
| `metrics.networkPolicy.enabled`, `allowedPeers` | Restrict exporter ingress to native NetworkPolicyPeer selectors. An empty list denies all exporter ingress. Game UDP stays reachable. |
| `service.type`, `port`, `nodePort`, `annotations` | External game Service. `port` is the external port; its target is `server.port`. |
| `resources`, `nodeSelector`, `tolerations`, `affinity` | Server resource and placement settings. Only amd64 is built. |
| `imagePullSecrets` | Kubernetes registry credential references. Public GHCR packages need none. |
| `podAnnotations`, `podLabels` | Extra metadata. Selector labels are reserved. |
| `securityContext`, `containerSecurityContext` | Pod and container security settings. The default UID, GID, and filesystem group are 1000. |

Each release owns one world and runs one replica with `Recreate`. Do not share its PVC with another running release or force-start a replacement while the old process still writes. Use a storage driver that honors `fsGroup`, or pre-provision writable storage for UID 1000. Disabling nonroot execution or changing volume ownership can prevent the game from starting.

### Official environment variables

| Variable | Default in this chart | Purpose |
| --- | --- | --- |
| `RSDW_OWNER_ID` | Required | Owner's EOS player ID. |
| `RSDW_PORT` | `7777` | Chart-owned. Set `server.port`. |
| `RSDW_SERVER_NAME` | `Dragonwilds` | Server creator name displayed by the game. |
| `RSDW_WORLD_NAME` | `World` | Name used for a newly generated world. |
| `RSDW_PASSWORD` | Empty | World password. Empty allows passwordless connections. |
| `RSDW_ADMINS` | Empty | Comma-separated administrator EOS IDs. |
| `RSDW_ADMIN_PASSWORD` | Empty | Server management password. Set it through a Secret. |
| `RSDW_ADDITIONAL_ARGS` | Empty | Upstream command-line argument string with quoted argument support. |
| `RSDW_AUTO_STOP_ON_UPDATE` | `false` | Upstream opt-in stop-on-update behavior. See limitations below. |
| `DEBUG` | `0` | `1` SteamCMD, `2` game logging, `3` both. |
| `STEAMAPPVALIDATE` | `0` | Set `1` to validate game files on startup. |

The upstream legacy alias `RSDW_ADDITIONAL_ARGUMENTS` remains available through `server.env`, but prefer `RSDW_ADDITIONAL_ARGS`. The upstream diagnostic `STEAMCMD_SPEW` and developer `DEVBUILD_PRESIGNED_URL` can also be supplied there. GameLift is outside this chart's deployment model. `GAMELIFT`, `STEAMAPPDIR`, `LD_PRELOAD`, and `RSDWAPI_*` are reserved alongside `RSDW_PORT`.

Explicit empty strings stay empty. Do not use upstream's `random` password option for a persistent installation; it changes on restart and prints passwords in logs. Values and inline INI text are stored in Helm release metadata and ConfigMaps. Use `extraEnv` Secret references for credentials.

```yaml
server:
  extraEnv:
    - name: RSDW_PASSWORD
      valueFrom:
        secretKeyRef:
          name: game-passwords
          key: world-password
    - name: RSDW_ADMIN_PASSWORD
      valueFrom:
        secretKeyRef:
          name: game-passwords
          key: admin-password
```

Create `game-passwords` in the release namespace using your secret-management tool or `kubectl create secret generic --from-file`. Secret values used in INI fields must contain no newlines. Token values must be nonempty bearer tokens; hexadecimal output from `openssl rand -hex 32` works. Restart the Deployment after changing external Secrets so the INI and API settings use the new values.

### Supply a full INI template

Jagex runs `envsubst` on this template at startup. It replaces the entire default template; include every setting you need. Repeated keys and Unreal array syntax stay intact. No INI parser or merge runs here.

```yaml
config:
  dedicatedServerIni: |
    [SectionsToSave]
    bCanSaveAllSections=true
    [/Script/Dominion.DedicatedServerSettings]
    AdminPassword=${RSDW_ADMIN_PASSWORD}
    WorldPassword=${RSDW_PASSWORD}
    ServerGuid=
    ServerName=${RSDW_SERVER_NAME}
    DefaultWorldName=${RSDW_WORLD_NAME}
    AdministratorList=(${RSDW_ADMINS})
    OwnerId=${RSDW_OWNER_ID}
```

The rendered file is `RSDragonwilds/Saved/Config/LinuxServer/DedicatedServer.ini` under the data volume. INI changes trigger a rollout. Substitution does not escape values or validate game-specific keys. Unknown game settings may be ignored. Player count is not an official environment variable; `server.env.RSDW_ADDITIONAL_ARGS` can pass Unreal overrides such as `-ini:Game:[/Script/Engine.GameSession]:MaxPlayers=12`. Support for such overrides depends on the game build.

## Import or restore a world

Place your `.sav` on a separate PVC in the same namespace, then configure its relative path.

```yaml
saveSeed:
  existingClaim: imported-world
  path: worlds/my-world.sav
```

The init container mounts that PVC read-only and copies the save into `RSDragonwilds/Saved/SaveGames`. It rejects absolute paths, traversal, and symlinks escaping the source volume. A temporary file and atomic rename protect interrupted copies. Any existing save or completed-import marker prevents another import. A missing requested source fails startup. The source PVC must support attachment to the selected node.

For example, populate a new source PVC through a temporary utility Pod that mounts it at `/seed`. Copy the file with `kubectl cp ./my-world.sav dragonwilds/UTILITY_POD:/seed/my-world.sav`. Stop that Pod before the server uses the claim. The source files must be readable by UID 1000.

Initial import is not restore. To restore over a current world, first back up the current data and stop the server with `kubectl -n dragonwilds scale deployment/game-rsdragonwilds --replicas=0`. Wait for its Pod to terminate. Attach the data PVC to a maintenance Pod, move existing saves and `.seed-complete` to a backup location, and copy the chosen save into `SaveGames`. Detach the maintenance Pod and restore one replica. Do not edit a live save. Helm's next upgrade also restores its fixed replica count of one.

Chart-created PVCs survive `helm uninstall` by default. Reattach one with `persistence.existingClaim`. Delete a retained PVC explicitly only after preserving the world elsewhere. Setting `persistence.retain=false` allows Helm uninstall to delete the claim; the storage class's reclaim policy then controls the underlying data.

## Scrape metrics

REST listens on `127.0.0.1` inside the Pod. No REST or RCON Service is created. The mod writes its complete settings on startup under `/home/steam/rsdw-dedicated/rsdwapi`, alongside persistent bans and logs. RCON and Discord remain disabled.

The exporter exposes a ClusterIP Service at `game-rsdragonwilds-metrics:7979`. It accepts arbitrary probe targets and holds a management API credential. Enable its NetworkPolicy and limit access to trusted Prometheus Pods. Your CNI must enforce NetworkPolicy.

```yaml
metrics:
  networkPolicy:
    enabled: true
    allowedPeers:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: monitoring
        podSelector:
          matchLabels:
            app.kubernetes.io/name: prometheus
  serviceMonitor:
    enabled: true
    labels:
      release: prometheus
```

Adjust selectors and ServiceMonitor labels for your Prometheus installation. Without Prometheus Operator, add both jobs below. The localhost target refers to the exporter's Pod, not Prometheus.

```yaml
scrape_configs:
  - job_name: dragonwilds-health
    metrics_path: /probe
    params:
      module: [health]
      target: ['http://127.0.0.1:8080/api/health']
    static_configs:
      - targets: ['game-rsdragonwilds-metrics.dragonwilds.svc:7979']
  - job_name: dragonwilds-players
    metrics_path: /probe
    params:
      module: [players]
      target: ['http://127.0.0.1:8080/api/players']
    static_configs:
      - targets: ['game-rsdragonwilds-metrics.dragonwilds.svc:7979']
```

| Metric | Meaning |
| --- | --- |
| `rsdw_engine_ready` | API engine readiness, 0 or 1. |
| `rsdw_uptime_seconds` | Mod process uptime in seconds. |
| `rsdw_players` | Player count reported by the REST API. |

Scraping `/metrics` alone only collects exporter metrics. HTTP failures return a failed probe. JSON extraction errors in upstream exporter v0.8.0 omit the affected metric and can still return HTTP 200. They never become a zero player count. Alert on both `up == 0` and missing required series, for example `absent_over_time(rsdw_players{job="dragonwilds-players"}[5m])`. Add equivalent absence checks for health metrics. Do not fill absent player metrics with zero in dashboards.

The API can report an empty roster after an internal read failure; the exporter cannot distinguish that case from zero players. It supplies no verified tick rate, tick latency, CPU, memory, or disk metrics. Use Kubernetes infrastructure metrics for resource use.

## Build and verify

```sh
python3 -m pip install PyYAML==6.0.3
bash tests/check.sh
docker build -t rsdragonwilds-server:dev .
bash tests/runtime.sh rsdragonwilds-server:dev
python3 tests/metrics.py
```

`tests/check.sh` exercises launcher patching, repeated startup preparation, save import, rejected paths, Helm variants, and invalid values. It runs ShellCheck when installed. `tests/runtime.sh` verifies the final image's library dependencies, UID, and installed hook without preloading the mod into a shell. On Linux, `tests/metrics.py` runs the real exporter against authenticated HTTP fixtures, including HTTP and malformed-JSON failures.

The launcher fixture comes from an actual current Steam download. The official unmodified image booted and created `SaveGames/silvarea.sav`. Local image build and dynamic dependency checks pass. Full modded game startup, engine readiness, player joins, imported-world selection, restart persistence, and graceful shutdown remain pending until exercised against the built image. Kubernetes runtime behavior also needs a real cluster check.

For live verification, install the chart into a disposable namespace with a test owner ID and dedicated PVC. Wait for readiness, then port-forward the metrics Service and query both probes.

```sh
kubectl -n dragonwilds port-forward service/game-rsdragonwilds-metrics 7979:7979
curl --fail --get http://127.0.0.1:7979/probe \
  --data-urlencode module=health --data-urlencode target=http://127.0.0.1:8080/api/health
curl --fail --get http://127.0.0.1:7979/probe \
  --data-urlencode module=players --data-urlencode target=http://127.0.0.1:8080/api/players
```

Inspect `/proc/*/maps` inside the server container to verify that only `RSDragonwildsServer-Linux-Shipping` maps `librsdwapi.so`. Join and leave the server to check player counts. Restart the Pod and verify world progress. Repeat with an imported test save, then change the seed and verify that existing progress wins. Check termination logs and saved progress before treating shutdown behavior as verified.

The image build rejects unexpected entrypoint structure. Startup rejects unknown downloaded launcher structure. Steam can update the game independently and break the mod's memory offsets. Upstream `1.1.1` also has known update-detection and process-monitoring limitations; do not rely on `RSDW_AUTO_STOP_ON_UPDATE` or prompt restart after a game crash without testing your game build. With API disabled, the Pod has no game readiness probe.

## Publish a release

Set both `version` and `appVersion` in `charts/rsdragonwilds/Chart.yaml` to the release version. Run the checks, commit, then push a matching tag such as `v0.1.0`.

```sh
git tag v0.1.0
git push origin v0.1.0
```

Actions validates the chart, builds the image, checks its dependencies, and publishes both artifacts using `GITHUB_TOKEN` with `packages:write`.

- Image: `ghcr.io/petzkod5/rsdragonwilds-server:0.1.0`
- Chart: `oci://ghcr.io/petzkod5/charts/rsdragonwilds`, version `0.1.0`

On the first publication, open each package's GitHub settings and set visibility to **Public**. A public repository does not automatically make GHCR packages public. If an existing package rejects the workflow, grant this repository Actions access in the package settings. Verify anonymous image and chart pulls from a clean client before announcing a release.

```sh
docker pull ghcr.io/petzkod5/rsdragonwilds-server:0.1.0
helm pull oci://ghcr.io/petzkod5/charts/rsdragonwilds --version 0.1.0
```

There is no single global Helm storage repository. GHCR hosts the OCI chart. For public discovery, create an [Artifact Hub](https://artifacthub.io/) account and register a Helm repository with URL `oci://ghcr.io/petzkod5/charts/rsdragonwilds`. Registration and ownership verification are manual account operations. Follow the [Artifact Hub Helm repository documentation](https://artifacthub.io/docs/topics/repositories/helm-charts/). `helm repo add` does not apply to this OCI distribution.

Our code uses the MIT license. [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES) retains Jagex and RSDWServerAPI notices and links to SteamCMD's separate terms.
