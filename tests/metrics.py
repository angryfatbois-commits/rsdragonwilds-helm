#!/usr/bin/env python3
"""Exercise the shipped exporter configuration against authenticated HTTP fixtures."""
import http.server
import json
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import yaml


class API(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        authorized = self.headers.get("Authorization") == "Bearer test-token"
        self.send_response(200 if authorized and self.path != "/failed" else 503)
        self.end_headers()
        responses = {"/api/health": {"engineReady": True, "uptimeSeconds": 123.5},
                     "/api/players": {"count": 4, "players": []}}
        self.wfile.write(json.dumps(responses[self.path]).encode() if self.path in responses else b"not-json")

    def log_message(self, *_):
        pass


documents = yaml.safe_load_all(subprocess.check_output([
    "helm", "template", "test", "charts/rsdragonwilds", "--set", "server.env.RSDW_OWNER_ID=test-owner",
    "--set", "api.bearerTokenSecret.name=test-token"], text=True))
config = next(doc["data"]["config.yml"] for doc in documents if doc["kind"] == "ConfigMap")
server = http.server.HTTPServer(("127.0.0.1", 0), API)
threading.Thread(target=server.serve_forever, daemon=True).start()
with socket.socket() as listener:
    listener.bind(("127.0.0.1", 0))
    exporter_port = listener.getsockname()[1]
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    path.chmod(0o755)
    (path / "config.yml").write_text(config)
    (path / "token").write_text("test-token")
    for file in path.iterdir():
        file.chmod(0o644)
    container = subprocess.check_output([
        "docker", "run", "--rm", "-d", "--network", "host", "-v", f"{path}:/run/rsdwapi:ro",
        "quay.io/prometheuscommunity/json-exporter:v0.8.0", "--config.file=/run/rsdwapi/config.yml",
        f"--web.listen-address=127.0.0.1:{exporter_port}"], text=True).strip()
    try:
        deadline = time.monotonic() + 30
        while True:
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{exporter_port}/metrics", timeout=1).close()
                break
            except (urllib.error.URLError, TimeoutError):
                if time.monotonic() > deadline:
                    raise
                time.sleep(0.2)

        def probe(module, endpoint):
            query = urllib.parse.urlencode({"module": module,
                                            "target": f"http://127.0.0.1:{server.server_port}{endpoint}"})
            with urllib.request.urlopen(f"http://127.0.0.1:{exporter_port}/probe?{query}", timeout=5) as response:
                return response.read().decode()

        health = probe("health", "/api/health")
        assert "rsdw_engine_ready 1\n" in health, health
        assert "rsdw_uptime_seconds 123.5\n" in health, health
        players = probe("players", "/api/players")
        assert "rsdw_players 4\n" in players, players
        try:
            probe("players", "/failed")
            raise AssertionError("HTTP failure unexpectedly succeeded")
        except urllib.error.HTTPError as error:
            assert error.code == 503, error
        malformed = probe("players", "/malformed")
        assert "rsdw_players" not in malformed, malformed
        print("Exporter maps authenticated health/players; HTTP failure is 503; malformed JSON omits metrics")
    finally:
        subprocess.run(["docker", "stop", "-t", "5", container], check=True, stdout=subprocess.DEVNULL)
        server.shutdown()
