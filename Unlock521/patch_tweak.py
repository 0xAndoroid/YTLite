import argparse
import hashlib
from pathlib import Path
import struct
import subprocess
import tempfile


# Offsets apply only to these unmodified upstream arm64 release binaries.
RELEASES = {
    "748f04787c8f08dd0e7df9c81519ba49a87e15f67ac720a9c1a08374e07b2e27": (
        "5.2.1",
        ((0x234B4, 0x2353C), (0x235C0, 0x23648), (0x23760, 0x237E4)),
    ),
    "bdcc4d4ccaa5835d35bc97ccbdfc1c3dff514cb7161848265dcc0585f364c0ca": (
        "5.2.2",
        ((0x238E8, 0x2396C), (0x23A84, 0x23B08), (0x234A4, 0x23528)),
    ),
}


def patch_binary(data):
    release = RELEASES.get(hashlib.sha256(data).hexdigest())
    if release is None:
        raise ValueError("Unsupported YTLite binary; expected an unmodified 5.2.1 or 5.2.2 arm64 release")

    version, branches = release
    patched = bytearray(data)
    # Keep the existing preference reads and main-queue dispatch, skipping only their gates.
    for source, target in branches:
        struct.pack_into("<I", patched, source, 0x14000000 | ((target - source) // 4))
    return version, patched


def patch_package(source, destination):
    with tempfile.TemporaryDirectory(prefix="ytlite-unlock-") as directory:
        root = Path(directory) / "package"
        subprocess.run(["dpkg-deb", "-R", str(source), str(root)], check=True)
        libraries = list(root.rglob("YTLite.dylib"))
        if len(libraries) != 1:
            raise ValueError("Expected exactly one YTLite.dylib in the package")
        library = libraries[0]
        version, patched = patch_binary(library.read_bytes())
        library.write_bytes(patched)
        subprocess.run(["ldid", "-S", str(library)], check=True)
        subprocess.run(["dpkg-deb", "--root-owner-group", "-b", str(root), str(destination)], check=True)
        return version


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Enable YTLite hooks and saved preferences before IPA signing")
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    arguments = parser.parse_args()
    try:
        version = patch_package(arguments.source, arguments.destination)
    except ValueError as error:
        parser.exit(1, f"{error}\n")
    print(f"YTLite {version}: hook registration and preference gates patched")
