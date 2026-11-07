import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
build = Path(sys.argv[1]).resolve()


def run(*args, **kwargs):
    return subprocess.run(args, check=True, timeout=120, **kwargs)


def host_gate():
    output = subprocess.check_output(["sysctl", "vm.swapusage"], text=True)
    used = re.search(r"used\s*=\s*([0-9.]+)([MG])", output)
    if not used:
        raise RuntimeError("Unreadable swap usage")
    gb = float(used[1]) / (1024 if used[2] == "M" else 1)
    load = os.getloadavg()[0]
    print(f"Build/test admission: swap {gb:.3f} GB, load1 {load:.2f}", flush=True)
    if gb >= 8 or load >= 36:
        raise RuntimeError("Host exceeds build/test limits")


host_gate()
run("make", "-f", str(root / "Native.mk"), "uikit-app", f"BUILD={build}")
runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))["runtimes"]
runtime = max((r for r in runtimes if r["isAvailable"] and ".iOS-" in r["identifier"]),
              key=lambda r: tuple(int(v) for v in r["version"].split(".")))
device = subprocess.check_output([
    "xcrun", "simctl", "create", f"agent-{os.environ.get('PIKA_TASK_ID', 'noise-filter')}-{os.getpid()}",
    "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro", runtime["identifier"],
], text=True).strip()
try:
    host_gate()
    run("xcrun", "simctl", "boot", device)
    run("xcrun", "simctl", "bootstatus", device, "-b")
    run("xcrun", "simctl", "install", device, str(build / "NoiseFilterTests.app"))
    result = subprocess.run([
        "xcrun", "simctl", "launch", "--console", device, "ee.andrew.noise-filter-tests",
    ], capture_output=True, text=True, timeout=100)
    (build / "uikit.log").write_text(result.stdout + result.stderr)
    print(result.stdout + result.stderr, flush=True)
    container = Path(subprocess.check_output([
        "xcrun", "simctl", "get_app_container", device, "ee.andrew.noise-filter-tests", "data",
    ], text=True).strip())
    for artifact in (container / "Documents").iterdir():
        if artifact.suffix in {".png", ".json"}:
            shutil.copyfile(artifact, build / artifact.name)
    result.check_returncode()
    if "NoiseFilter UIKit: PASS" not in result.stdout + result.stderr:
        raise RuntimeError("UIKit checks did not report completion")
finally:
    subprocess.run(["xcrun", "simctl", "shutdown", device], check=False, timeout=30)
    run("xcrun", "simctl", "delete", device)
