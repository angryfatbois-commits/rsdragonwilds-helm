#!/usr/bin/env python3
"""Render the chart and verify its deployment contract. Requires PyYAML and Helm."""
import json
import subprocess
import tempfile
from pathlib import Path

import yaml

CHART = "charts/rsdragonwilds"
REQUIRED = {"server": {"env": {"RSDW_OWNER_ID": "test-owner"}},
            "api": {"bearerTokenSecret": {"name": "test-token"}}}


def render(values=None, valid=True, defaults=True):
    with tempfile.TemporaryDirectory() as directory:
        args = ["helm", "template", "test", CHART]
        for index, data in enumerate(([REQUIRED] if defaults else []) + [values or {}]):
            path = Path(directory) / f"values-{index}.json"
            path.write_text(json.dumps(data))
            args.extend(["-f", str(path)])
        result = subprocess.run(args, text=True, capture_output=True)
        if not valid:
            assert result.returncode != 0, f"Expected rejection: {values}"
            assert "Error:" in result.stderr, result.stderr
            return
        assert result.returncode == 0, result.stderr
        return [item for item in yaml.safe_load_all(result.stdout) if item]


def resource(documents, kind):
    return next(item for item in documents if item["kind"] == kind)


def pod(documents):
    return resource(documents, "Deployment")["spec"]["template"]["spec"]


documents = render()
deployment = resource(documents, "Deployment")
assert deployment["spec"]["replicas"] == 1
assert deployment["spec"]["strategy"] == {"type": "Recreate"}
assert resource(documents, "PersistentVolumeClaim")["metadata"]["annotations"]["helm.sh/resource-policy"] == "keep"
assert "storageClassName" not in resource(documents, "PersistentVolumeClaim")["spec"]
game = pod(documents)["containers"][0]
env = {entry["name"]: entry for entry in game["env"]}
assert env["RSDW_PASSWORD"]["value"] == ""
assert env["RSDW_PORT"]["value"] == "7777"
assert len(env) == len(game["env"])
assert pod(documents)["containers"][1]["image"].endswith(":v0.8.0")
config = yaml.safe_load(resource(documents, "ConfigMap")["data"]["config.yml"])
assert config["modules"]["players"]["metrics"][0]["path"] == "{.count}"
assert config["modules"]["health"]["http_client_config"]["authorization"]["credentials_file"] == "/run/rsdwapi/token"

secret = {"name": "RSDW_PASSWORD", "valueFrom": {"secretKeyRef": {"name": "passwords", "key": "world"}}}
documents = render({"server": {"port": 8888, "extraEnv": [secret]}})
game = pod(documents)["containers"][0]
assert [entry for entry in game["env"] if entry["name"] == "RSDW_PASSWORD"] == [secret]
assert game["ports"][0]["containerPort"] == 8888
assert next(e for e in game["env"] if e["name"] == "RSDW_PORT")["value"] == "8888"
render({"server": {"env": {"RSDW_OWNER_ID": ""}, "extraEnv": [dict(secret, name="RSDW_OWNER_ID")]}})

ini = "[Server]\nServerName=${RSDW_SERVER_NAME}\n+Repeated=one\n+Repeated=two\n"
documents = render({"config": {"dedicatedServerIni": ini}, "persistence": {"existingClaim": "world-data"},
                    "saveSeed": {"existingClaim": "import-data", "path": "folder/custom.sav"}})
assert not any(item["kind"] == "PersistentVolumeClaim" for item in documents)
assert resource(documents, "ConfigMap")["data"]["DedicatedServer.ini"] == ini
assert pod(documents)["initContainers"][0]["args"][-1].endswith("/Saved/SaveGames")
assert next(v for v in pod(documents)["volumes"] if v["name"] == "seed")["persistentVolumeClaim"]["readOnly"]
assert pod(documents)["initContainers"][0]["volumeMounts"][1]["readOnly"]
assert deployment["spec"]["template"]["metadata"]["annotations"]["checksum/config"] != resource(documents, "Deployment")["spec"]["template"]["metadata"]["annotations"]["checksum/config"]

documents = render({"api": {"enabled": False}, "metrics": {"enabled": False}})
assert len(pod(documents)["containers"]) == 1
assert not any(item["kind"] == "ConfigMap" for item in documents)
assert "readinessProbe" not in pod(documents)["containers"][0]
documents = render({"metrics": {"serviceMonitor": {"enabled": True}, "networkPolicy": {"enabled": True}}})
endpoints = resource(documents, "ServiceMonitor")["spec"]["endpoints"]
assert len(endpoints) == 2
assert [e["params"]["module"][0] for e in endpoints] == ["health", "players"]
assert all(e["path"] == "/probe" for e in endpoints)
assert len(resource(documents, "NetworkPolicy")["spec"]["ingress"]) == 1
documents = render({"persistence": {"storageClass": ""}, "image": {"digest": "sha256:" + "a" * 64}})
assert resource(documents, "PersistentVolumeClaim")["spec"]["storageClassName"] == ""
assert "@sha256:" in pod(documents)["containers"][0]["image"]

render(valid=False, defaults=False)
for values in [
    {"api": {"bearerTokenSecret": {"name": ""}}},
    {"api": {"enabled": False}},
    {"api": {"port": 7979}},
    {"metrics": {"enabled": False, "serviceMonitor": {"enabled": True}}},
    {"server": {"extraEnv": [secret, secret]}},
    {"server": {"extraEnv": [{"name": "RSDW_PORT", "value": "1234"}]}},
    {"server": {"env": {"RSDW_PORT": "1234"}}},
    {"server": {"env": {"LD_PRELOAD": "/bad.so"}}},
    {"server": {"env": {"RSDW_SERVER_NAME": "bad\nname"}}},
    {"server": {"port": 65536}},
    {"saveSeed": {"existingClaim": "seed"}},
    {"saveSeed": {"existingClaim": "seed", "path": "../world.sav"}},
    {"saveSeed": {"existingClaim": "seed", "path": "/world.sav"}},
    {"service": {"type": "ClusterIP", "nodePort": 31000}},
    {"replicaCount": 2},
]:
    render(values, valid=False)
subprocess.run(["helm", "lint", CHART, "--strict", "--set", "server.env.RSDW_OWNER_ID=test-owner",
                "--set", "api.bearerTokenSecret.name=test-token"], check=True)
print("Helm rendering and invalid configuration checks passed")
