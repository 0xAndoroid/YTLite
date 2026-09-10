# Unlock

The build helper patches the upstream package before IPA injection/signing.
Supported inputs: unmodified YTLite 5.2.1 and 5.2.2 `iphoneos-arm` release
packages (containing arm64 binaries).
Other binaries stop the build; offsets are checked against the full SHA-256.

| Component | Behavior |
| --- | --- |
| `patch_tweak.py` | Runs hook-registration callbacks on the main queue without waiting for activation; reads saved boolean/integer preferences without the access gate. |
| `Unlock.x` | Suppresses the activation reminder via `dontRemindAccess`; preserves the original settings pages. |

Both components are required. Existing ad-blocking preferences stay unchanged.

Verification (requires macOS command-line tools, `uv`, and `dpkg-deb`):

```sh
uv run Unlock521/tests/verify_release.py /path/to/ytplus.deb
sh Unlock521/tests/verify_companion.sh
```

The release check executes actual ARM64 preference and registration functions in
Unicorn, with Foundation/libdispatch calls simulated. The companion check loads
the compiled library against fixture settings pages and an isolated preferences
suite. Neither verifies live YouTube playback; check the settings page, home feed,
and video playback after sideloading.
