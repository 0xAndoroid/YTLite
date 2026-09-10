#!/bin/sh
set -eu

build_dir=$(mktemp -d)
trap '/bin/rm -rf "$build_dir"' EXIT

xcrun --sdk macosx clang -fobjc-arc -Wall -Werror -framework Foundation \
    -dynamiclib -x objective-c Unlock521/Unlock.x -o "$build_dir/Unlock.dylib"
xcrun --sdk macosx clang -fobjc-arc -Wall -Werror -framework Foundation \
    Unlock521/tests/verify_companion.m -o "$build_dir/verify_companion"
"$build_dir/verify_companion" "$build_dir/Unlock.dylib"
