#!/bin/sh
set -eu
build_dir=$(mktemp -d "${TMPDIR:?}/noise-filter-checks.XXXXXX")
trap '/bin/rm -rf "$build_dir"' EXIT
node NoiseFilter/bundle.mjs "$build_dir/NFContract.inc"
node NoiseFilter/tests/fixtures.mjs "$build_dir/NFContract.inc" "$build_dir/fixtures.json"
for source in NFContract NFHTTP NFService; do
    xcrun --sdk macosx clang -fobjc-arc -Wall -Werror -INoiseFilter -I"$build_dir" \
        -c "NoiseFilter/$source.m" -o "$build_dir/$source.o"
done
xcrun --sdk macosx clang -fobjc-arc -Wall -Werror -framework Foundation \
    -framework JavaScriptCore -framework Security -INoiseFilter \
    "$build_dir"/*.o NoiseFilter/tests/check.m -o "$build_dir/check"
result=0
"$build_dir/check" "$build_dir/fixtures.json" || result=1
if xcrun --sdk macosx clang++ -fobjc-arc -Wall -Werror -framework Foundation \
    -framework JavaScriptCore -framework Security -INoiseFilter \
    "$build_dir"/*.o NoiseFilter/tests/linkage.mm -o "$build_dir/linkage"; then
    "$build_dir/linkage" || result=1
else
    result=1
fi
exit "$result"
