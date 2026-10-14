# Noise Filter companion

This first part supplies the native classification service. Feed/caption hooks and the native settings entry belong to the following integration PR; this package alone does not filter the app.

## Contract

`verdict.js` is an exact import of `extension/verdict.js` from `0xAndoroid/yt-noise-filter` at `8416a924642c866107c1734bedb75aaed993697a`. Its SHA-256 is `ebdb42863f1960b22942352e195c9ac3faf256759bb9ea9646108c58cef43c5b`. The owner authorized publishing this module in this public fork. `bundle.mjs` rejects changed bytes, removes only ES-module exports, and embeds the module for JavaScriptCore. Prompts, labels, reasons, uncertainty rules, request generation and answer validation are not rewritten in Objective-C.

The app requires iOS 17. JavaScriptCore supplies the module's ECMAScript APIs, including `Object.hasOwn` and `String.prototype.toWellFormed` ([Safari 16.4 release notes](https://developer.apple.com/documentation/safari-release-notes/safari-16_4-release-notes)). It needs no browser globals, fetch, Web Crypto or TextEncoder. SHA-256 and transport stay native.

## Native state

Call `NFService` on the main thread. URLSession delegate completions also run there. Verdicts are JSON data in a separate defaults domain; `v:<guidance hash>:<video ID>` names the exact effective guidance used in the request. Allow choices use separate `a:<video ID>` keys. Instruction changes preserve other namespaces; category/strictness changes only read scores. Key changes and Clear verdicts invalidate old completions.

The generic-password Keychain item uses service `com.andoroid.youtube-noise-filter`, account `openai-api-key`, and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. No shared access group or synchronization is configured. The key never enters defaults, JavaScriptCore, resources or logs.

At most four video jobs run at once. Each reads a bounded ordinary watch-page player response and JPEG, then calls the contract's fixed Decisions endpoint through an ephemeral URLSession without cookies, URL caching or redirects. Failures are visible and uncached; HTTP 429 delays new jobs without retry timers. Caption upgrades require a matching current view token and preserve the metadata verdict on failure.

## Checks and package

Run `sh NoiseFilter/tests/check.sh` on macOS with Xcode and Node 22 or later. It compares JavaScriptCore with Node evaluating the imported module and exercises real production service code through fixture NSURLProtocol responses and an isolated Keychain/defaults domain. The fixture never contacts YouTube or OpenAI.

The PR workflow calls `_build_tweaks.yml`, which runs these checks and builds the actual Theos companion. Its `built-debs` artifact includes `noise-filter.deb`; existing main/beta packaging already injects every built `.deb`. Unlock521 and activation behavior are unchanged. Native fixture checks and compilation do not prove live device behavior.
