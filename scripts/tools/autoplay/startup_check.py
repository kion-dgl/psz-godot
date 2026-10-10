#!/usr/bin/env python3
"""Run the real bootstrap matrix with isolated player data (Godot 4.5+).
Usage: GODOT=/path/to/godot python3 scripts/tools/autoplay/startup_check.py
No manifest or player files in the working checkout are modified.
"""
import os
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
import time
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid

class SlowFixtureHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def copyfile(self, source, output):
        while chunk := source.read(65536):
            output.write(chunk)
            output.flush()
            time.sleep(0.025)


root = Path(__file__).resolve().parents[3]
godot = os.environ.get("GODOT", "godot")
with tempfile.TemporaryDirectory(prefix="psz-startup-project-") as directory:
    project = Path(directory)
    for source in root.iterdir():
        if source.name not in {"project.godot", ".git", ".env"}:
            (project / source.name).symlink_to(source, target_is_directory=source.is_dir())
    user_name = "psz-startup-test-" + uuid.uuid4().hex
    settings = (root / "project.godot").read_text().replace(
        "[application]", "[application]\nconfig/use_custom_user_dir=true\n"
        f'config/custom_user_dir_name="{user_name}"', 1)
    (project / "project.godot").write_text(settings)
    fixtures = project / "http-fixtures"
    fixtures.mkdir()
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(SlowFixtureHandler, directory=str(fixtures)))
    Thread(target=server.serve_forever, daemon=True).start()
    environment = os.environ.copy()
    environment["PSZ_STARTUP_FIXTURE_PATH"] = str(fixtures / "fixture.pck")
    environment["PSZ_STARTUP_FIXTURE_URL"] = f"http://127.0.0.1:{server.server_port}/fixture.pck"
    result = subprocess.run([godot, "--headless", "--path", str(project),
        "res://scripts/tools/startup_probe.tscn"], capture_output=True, text=True, timeout=120, env=environment)
    server.shutdown()
    server.server_close()
    output = result.stdout + result.stderr
    print(output)
    # The probe prints the engine-resolved directory; delete only this run's
    # UUID-named fixture directory, never a player's normal user directory.
    for line in result.stdout.splitlines():
        if line.startswith("[startup-probe] userdir: "):
            data = Path(line.removeprefix("[startup-probe] userdir: "))
            if data.name == user_name:
                shutil.rmtree(data)
    raise SystemExit(0 if result.returncode == 0 and "[startup-probe] DONE ok" in output
        and "SCRIPT ERROR" not in output else 1)
