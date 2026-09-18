import base64
import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import threading
import time
import urllib.request
import urllib.error

import pytest


TEMPLATE = Path(__file__).resolve().parents[2] / "template"


class Backend(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("Upgrade", "").lower() == "websocket":
            key = self.headers["Sec-WebSocket-Key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
            self.send_response(101)
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.send_header("Sec-WebSocket-Accept", base64.b64encode(hashlib.sha1(key.encode()).digest()).decode())
            self.send_header("X-Upstream-Path", self.path)
            self.end_headers()
            return
        body = json.dumps({"path": self.path}).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_arguments):
        pass


def available_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


@pytest.mark.parametrize("folder,base", [("example-single-web-app-vite", "/"), ("example-multi-web-app/app", "/app/")])
def test_real_vite_http_websocket_hmr_and_build(tmp_path, folder, base):
    executable = shutil.which("vite")
    if not executable or not shutil.which("node"):
        pytest.skip("Vite CLI and Node required for live proxy integration")
    vite = Path(executable).resolve().parents[1]
    modules = tmp_path / "node_modules"
    modules.mkdir()
    (modules / "vite").symlink_to(vite, target_is_directory=True)
    for name, source in {
        "@vitejs/plugin-react": 'export default () => ({name:"fixture-react"});',
        "@tailwindcss/vite": 'export default () => ({name:"fixture-tailwind"});',
        "@tanstack/router-plugin": 'export const tanstackRouter = () => ({name:"fixture-router"});',
    }.items():
        package = modules / name
        package.mkdir(parents=True)
        (package / "package.json").write_text(json.dumps({"type": "module", "exports": {".": "./index.js", "./vite": "./index.js"}}))
        (package / "index.js").write_text(source)
    shutil.copy2(TEMPLATE / "apps" / folder / "vite.config.ts", tmp_path / "vite.config.ts")
    (tmp_path / "package.json").write_text('{"type":"module"}')
    (tmp_path / "index.html").write_text('<h1>frontend</h1><script type="module" src="/src/main.ts"></script>')
    (tmp_path / "src").mkdir()
    (tmp_path / "src/main.ts").write_text('document.title = __APP_NAME__; console.log(import.meta.env.MODE);')
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Backend)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = available_port()
    environment = {"PATH": os.environ["PATH"], "HOME": str(tmp_path), "WEB_APP_PORT": str(port),
                   "WEB_APP_PREFIX": "/app/", "API_PREFIX": "/api.v1", "ENGINE_PREFIX": "/engine",
                   "API_HOST": "127.0.0.1", "ENGINE_HOST": "127.0.0.1",
                   "API_PORT": str(server.server_port), "ENGINE_PORT": str(server.server_port),
                   "UNDECLARED_SECRET": "private-fixture-sentinel"}
    log = (tmp_path / "vite.log").open("w+")
    process = subprocess.Popen([executable, "--config", str(tmp_path / "vite.config.ts")],
                               cwd=tmp_path, env=environment, stdout=log, stderr=log)
    try:
        deadline = time.monotonic() + 15
        while True:
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{port}{base}", timeout=1) as response:
                    assert b"frontend" in response.read()
                break
            except OSError:
                if process.poll() is not None or time.monotonic() > deadline:
                    log.seek(0)
                    pytest.fail(log.read())
                time.sleep(0.1)
        for path in ("/api.v1/ready?value=1", "/engine/ready"):
            with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}") as response:
                assert json.load(response)["path"] == path
        for path in ("/apiXv1/ready", "/api.v12/ready"):
            try:
                response = urllib.request.urlopen(f"http://127.0.0.1:{port}{path}")
            except urllib.error.HTTPError as error:
                response = error
            with response:
                assert b'"path":' not in response.read()
        with urllib.request.urlopen(f"http://127.0.0.1:{port}{base}@vite/client") as response:
            assert "javascript" in response.headers["Content-Type"]
        with urllib.request.urlopen(f"http://127.0.0.1:{port}{base}src/main.ts") as response:
            assert b"private-fixture-sentinel" not in response.read()
        with socket.create_connection(("127.0.0.1", port), timeout=3) as connection:
            connection.sendall((f"GET /engine/socket HTTP/1.1\r\nHost: localhost:{port}\r\n"
                                "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\n"
                                "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n").encode())
            headers = b""
            while b"\r\n\r\n" not in headers:
                chunk = connection.recv(4096)
                assert chunk
                headers += chunk
            assert b"101" in headers.splitlines()[0]
            assert b"/engine/socket" in headers
        build_env = {key: value for key, value in environment.items() if key in {"PATH", "HOME", "WEB_APP_PREFIX"}}
        result = subprocess.run([executable, "build"], cwd=tmp_path, env=build_env,
                                text=True, capture_output=True, timeout=30)
        assert result.returncode == 0, result.stderr
    finally:
        process.terminate()
        process.wait(timeout=5)
        server.shutdown()
        server.server_close()
        log.close()


def test_next_rewrites_are_dev_only_and_keep_root_backend_prefixes(tmp_path):
    node = shutil.which("node")
    if not node:
        pytest.skip("Node required for config evaluation")
    package = tmp_path / "node_modules/next"
    package.mkdir(parents=True)
    (tmp_path / "package.json").write_text('{"type":"module"}')
    (package / "package.json").write_text('{"type":"module","exports":{"./constants":"./constants.js"}}')
    (package / "constants.js").write_text('export const PHASE_DEVELOPMENT_SERVER = "dev";')
    shutil.copy2(TEMPLATE / "apps/example-dashboard-nextjs/next.config.ts", tmp_path / "next.config.ts")
    code = 'import config from "./next.config.ts"; console.log(JSON.stringify(await config(process.argv[1]).rewrites()));'
    env = {"PATH": os.environ["PATH"], "DASHBOARD_PREFIX": "/dashboard", "API_PREFIX": "/api", "ENGINE_PREFIX": "/engine",
           "API_HOST": "127.0.0.1", "ENGINE_HOST": "127.0.0.1", "API_PORT": "8000", "ENGINE_PORT": "8080"}
    result = subprocess.run([node, "--input-type=module", "-e", code, "dev"], cwd=tmp_path, env=env,
                            text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, result.stderr
    routes = json.loads(result.stdout)
    assert routes[0] == {"source": "/api/:path*", "destination": "http://127.0.0.1:8000/api/:path*", "basePath": False}
    assert routes[1]["source"] == "/engine/:path*"
    result = subprocess.run([node, "--input-type=module", "-e", code, "build"], cwd=tmp_path,
                            env={"PATH": os.environ["PATH"], "DASHBOARD_PREFIX": "/dashboard"},
                            text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == []
