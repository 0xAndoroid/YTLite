"""Builds the simulator test host and runs it in a throwaway simulator, once with the
HackerTube Home switch off and once with it on.

    run.py BUILD_DIR          Home loads the test host's own fixture server
    run.py BUILD_DIR --live   Home loads https://hackertube.org/; also saves live.png
"""
import json
import os
import shutil
import socket
import subprocess
import sys
import threading
from pathlib import Path

root = Path(__file__).resolve().parents[1]
build = Path(sys.argv[1]).resolve()
live = "--live" in sys.argv[2:]
bundle = "ee.andrew.hackertube-tests"


def run(*args, **kwargs):
    return subprocess.run(args, check=True, timeout=300, **kwargs)


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def launch(device):
    """Runs the test host to completion and returns its output."""
    process = subprocess.Popen(["xcrun", "simctl", "launch", "--console", device, bundle],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    watchdog = threading.Timer(240, process.kill)
    watchdog.start()
    lines = []
    for line in process.stdout:
        print(line, end="", flush=True)
        lines.append(line)
        if line.strip() == "HKT-SCREENSHOT":
            # simctl cannot always write screenshots outside the boot volume.
            shot = Path("/tmp") / f"hackertube-live-{os.getpid()}.png"
            run("xcrun", "simctl", "io", device, "screenshot", str(shot))
            shutil.move(shot, build / "live.png")
    process.wait()
    watchdog.cancel()
    return "".join(lines)


# The fixture port is compiled into the test host, so it is rebuilt for every run.
make = ["make", "-B", "-C", str(root), "test-app", f"BUILD={build}"]
if not live:
    make.append(f"SITE_URL=http://127.0.0.1:{free_port()}/")
run(*make)

runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))["runtimes"]
runtime = max((r for r in runtimes if r["isAvailable"] and r["platform"] == "iOS"),
              key=lambda r: tuple(int(v) for v in r["version"].split(".")))
phone = next(d["identifier"] for d in runtime["supportedDeviceTypes"] if d["productFamily"] == "iPhone")
name = f"agent-{os.environ.get('PIKA_TASK_ID', 'hackertube')}-{os.getpid()}"
device = subprocess.check_output(["xcrun", "simctl", "create", name, phone, runtime["identifier"]], text=True).strip()
try:
    run("xcrun", "simctl", "boot", device)
    run("xcrun", "simctl", "bootstatus", device, "-b")
    run("xcrun", "simctl", "install", device, str(build / "HackerTubeTests.app"))
    output = launch(device) + launch(device)
finally:
    subprocess.run(["xcrun", "simctl", "shutdown", device], check=False, timeout=60)
    run("xcrun", "simctl", "delete", device)

(build / "checks.log").write_text(output)
passed = all(f"HackerTube checks with the switch {state}: PASS" in output for state in ("off", "on"))
if not passed or "FAIL" in output:
    sys.exit("HackerTube checks failed")
