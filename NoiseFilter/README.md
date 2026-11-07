# Noise Filter companion

**Diagnostic checkpoint: this build does not hide Home videos yet.** It provides TypeSafe classification, native Settings and a bounded capture of actual Home row metadata. The remaining dependency is a verified connection between a displayed Home card and its primary video, followed by native layout removal. Simulator fixtures and installation do not satisfy phone filtering acceptance.

This companion lives on the long-lived `noise-filter` branch. Integration PRs target that branch, never `main`. It has no paid-feature source dependency. Its PR workflow builds only this companion.

## Settings

Starting on YouTube's existing Settings screen, the companion adds a **Noise filter** navigation button without replacing existing buttons. It opens these controls:

- **TypeSafe API key:** Add, Replace or Remove. Input is secure; no key ships with the app.
- **Filter Home videos**, category switches, and Lenient / Normal / Strict cutoffs. These settings are prepared for the Home integration; this diagnostic build does not suppress rows.
- **Custom instructions:** explicit Save, with a 1,000 UTF-16-unit limit.
- **Activity:** request attempts, HTTP 200 responses, cached judgments, reported input tokens, errors, Clear judgments and Capture Home diagnostics.

These labels and controls have a UIKit fixture. Their entry point in the actual YouTube 21.44.4 app still needs the phone checkpoint below. No native caption binding is implemented; the service's existing caption-upgrade API remains available to a future caller.

## TypeSafe contract and state

`verdict.js` is an exact import of `extension/verdict.js` at yt-noise-filter commit `6d3a427826757fd14402a27841e21aeef56281a2`, SHA-256 `c07984593062497bb86d0be560cedc6ec45c6066f498eab67ac3f405f813092a`. The build verifies those bytes, removes ES-module exports and evaluates the module in JavaScriptCore. Shared X helpers remain part of that pinned module but are not called by this companion.

Requests use [TypeSafe System One](https://docs.typesafe.ai/api/system-one), model `jev-1.14.0`, named choice questions and keyed probability answers. The native transport supplies the required [image opt-in header](https://docs.typesafe.ai/images), a UUID-referenced JPEG and the `hqdefault.jpg` thumbnail route. Requests use an ephemeral URLSession without cookies, URL caching or redirects. At most four video jobs run at once. Failed requests remain uncached. HTTP 429 holds new jobs according to Retry-After seconds or an HTTP date; absent or unusable values use a fallback delay. There is no retry timer.

Call `NFService` on main. Its shared instance is created only on main after protected data becomes available. The TypeSafe key uses generic-password service `com.andoroid.youtube-noise-filter`, account `typesafe-api-key`, with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. No shared access group or synchronization is requested. The old `openai-api-key` item is neither read nor migrated. A transient Keychain failure is distinct from absence; interpret `hasKey` together with `keychainStatus`, not as proof of a usable credential.

Defaults hold settings overrides and JSON verdicts, never the key. Verdict namespaces include the endpoint, requested model, video policy and effective instructions; changing category switches or cutoffs reuses scores. Clear judgments removes every verdict namespace, but keeps the key, settings, allow choices and cumulative counters. Key changes and Clear invalidate earlier completions. Each cached result records its local request ID, requested model, provider-reported model when present, and judgment time. The attempt counter counts submissions to the native transport, not proof of receipt by TypeSafe. HTTP responses and valid cached judgments provide separate evidence.

Builds stamp their Git head into diagnostics, with `-modified` for an uncommitted companion. Requires a Git checkout, iOS 17 or later, Xcode and Node 22 or later.

## Home identity capture

The capture hooks `YTInnerTubeCollectionViewController` display/appearance callbacks after their original implementations. It uses the native section-list `isHomeFeed` predicate and current presentation-to-model index conversion. Exact method encodings are checked before installation; inherited methods are overridden on the target class, not on UIKit's shared superclasses.

**Capture Home diagnostics** arms a one-minute admission window for at most eight visible-row observations. It records row frames and class/getter paths, including the actual collection cell's node and element. Quoted element-proto values are redacted except 11-character video-ID values in video-ID fields and canonical YouTube watch URLs with all other query data removed. It does not export raw element bytes, API keys or custom instructions. Captured IDs remain candidates until correlated with real displayed cards.

The capture does not replace feed models, change item counts, write frames or hidden flags, or call the classifier. It does not invoke the renderer's elementData getter, which can build and cache data through native block execution. Results are written atomically, with complete file protection, to `Documents/NoiseFilter-diagnostics.json` in the app's own container. The first observed viewport also writes `Documents/NoiseFilter-Home.png`, a snapshot of the Home collection only. Its SHA-256, capture time, bounds in points and image scale are recorded in the JSON, so candidate IDs can be compared with the displayed cards. This image can contain personal feed content and stays local; it is not a full-device screenshot. Capture is opt-in; no automatic capture starts at launch. It has no timer, background polling or upload. Investigation-only capture code will be removed once the production binding is established.

### Required phone checkpoint

Only after coordinator review and merge into `noise-filter`, build the companion from that merged branch and prepare an in-place package. Device actions require the coordinator's separate go; never uninstall the app.

1. Keep the iPhone connected and unlocked. After the authorized install, open the same YouTube app. Do not enter an API key for this identity-only checkpoint.
2. Starting at YouTube Settings, open **Noise filter** and select **Capture Home diagnostics** under Activity.
3. Return to Home and scroll through several actual video cards during the next minute. The capture leaves them visible.
4. Retrieve the diagnostics JSON and matched Home PNG through the authorized app-container route. Check the companion build, hook status, Home callback count and observations before drawing conclusions.

A successful capture proves only an observation path. The final acceptance still requires a key entered through these settings, real successful judgments, actual noise videos removed from Home without gaps, kept cards unchanged, and a non-Home control. A key and judgments with no hiding falsify completion.

## Focused checks and build

From the repository root, with a task-owned build directory:

```sh
build="$(mktemp -d "${TMPDIR:?}/noise-filter.XXXXXX")"
sh NoiseFilter/tests/check.sh
uv run --no-project python NoiseFilter/tests/run-uikit.py "$build"
make -f NoiseFilter/Native.mk BUILD="$build"
```

The service fixture uses fake HTTP responses and isolated fake-key Keychain/defaults entries. It checks the shared Node/JavaScriptCore contract, credential and cache generations, caption ownership, concurrency, usage and rate holds. The UIKit fixture uses real UIKit with stand-in YouTube classes, fake Keychain calls and no network. It exercises the actual Settings/hook installers, key and preference actions, rendered instructions, bounded capture/redaction, and unchanged collection geometry. Its task-owned simulator is shut down and deleted afterward. None of these fixtures runs the real YouTube feed or establishes provider access.

`Native.mk` produces an unsigned arm64 `NoiseFilter.dylib`; it compiles no other tweak. The existing Theos Makefile also builds only this companion when invoked in this directory. Do not invoke the repository's shared tweak-packaging helper for this work: it contains separate paid-feature build steps.

For the supplied signed YouTube baseline, replace only `Payload/YouTube.app/Frameworks/NoiseFilter.dylib`, then sign that library and reseal the app with the existing identity and root entitlements. Keep all other executable bytes and nested signatures unchanged. Verify the complete file-backed Mach-O sections of the app executable before/after resealing, exact bytes of every other executable, the existing app/Keychain entitlement slots and the final deep signature. Keep source hashes and signing receipts with the package. The installed app's bundle ID remains `ee.andrew.youtube`.
