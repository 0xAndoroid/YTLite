#!/bin/sh
set -eu
build_dir=$(mktemp -d "${TMPDIR:?}/noise-filter-checks.XXXXXX")
trap '/bin/rm -rf "$build_dir"' EXIT
node NoiseFilter/bundle.mjs "$build_dir/NFContract.inc"
node NoiseFilter/tests/fixtures.mjs "$build_dir/NFContract.inc" "$build_dir/fixtures.json"
xcrun --sdk macosx clang -fobjc-arc -Wall -Werror -framework Foundation \
    -framework JavaScriptCore -framework Security -INoiseFilter -I"$build_dir" \
    NoiseFilter/NFContract.m NoiseFilter/NFHTTP.m NoiseFilter/NFService.m \
    NoiseFilter/tests/check.m -o "$build_dir/check"
"$build_dir/check" "$build_dir/fixtures.json"
