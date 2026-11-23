"""Builds the test host and runs it in a throwaway simulator.

    run.py BUILD_DIR           Full suite with the test host's own fixture server
    run.py BUILD_DIR --smoke   One launch covering Home and a card tap on the fixture
    run.py BUILD_DIR --live    Home loads https://hackertube.org/; also saves live.png
"""
import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import threading
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description="Run the HackerTube simulator fixture.")
parser.add_argument("build_dir", type=Path)
mode = parser.add_mutually_exclusive_group()
mode.add_argument("--smoke", action="store_true")
mode.add_argument("--live", action="store_true")
args = parser.parse_args()
build = args.build_dir.resolve()
bundle = "ee.andrew.hackertube-tests"


def run(*args, **kwargs):
    return subprocess.run(args, check=True, timeout=300, **kwargs)


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def launch(device, *app_args):
    process = subprocess.Popen(["xcrun", "simctl", "launch", "--console", device, bundle, *app_args],
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
    status = process.wait()
    watchdog.cancel()
    return status, "".join(lines)


# The fixture port is compiled into the test host, so it is rebuilt for every run.
make = ["make", "-B", "-C", str(root), "test-app", f"BUILD={build}"]
if not args.live:
    make.append(f"SITE_URL=http://127.0.0.1:{free_port()}/")
run(*make)

runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))["runtimes"]
runtime = max((r for r in runtimes if r["isAvailable"] and r["platform"] == "iOS"),
              key=lambda r: tuple(int(v) for v in r["version"].split(".")))
phone = next(d["identifier"] for d in runtime["supportedDeviceTypes"] if d["productFamily"] == "iPhone")
name = f"agent-{os.environ.get('PIKA_TASK_ID', 'hackertube')}-{os.getpid()}"
device = subprocess.check_output(["xcrun", "simctl", "create", name, phone, runtime["identifier"]], text=True).strip()
if args.smoke:
    launches = [(("-HackerTubeHomeEnabled", "YES", "--smoke"), "HackerTube smoke: PASS")]
else:
    launches = [((), f"HackerTube checks with the switch {state}: PASS") for state in ("off", "on")]
output = []
passed = True
try:
    run("xcrun", "simctl", "boot", device)
    run("xcrun", "simctl", "bootstatus", device, "-b")
    run("xcrun", "simctl", "install", device, str(build / "HackerTubeTests.app"))
    for app_args, marker in launches:
        status, log = launch(device, *app_args)
        output.append(log)
        passed = passed and status == 0 and marker in log.splitlines() and "FAIL" not in log
finally:
    subprocess.run(["xcrun", "simctl", "shutdown", device], check=False, timeout=60)
    run("xcrun", "simctl", "delete", device)

(build / "checks.log").write_text("".join(output))
if not passed:
    sys.exit("HackerTube checks failed")
