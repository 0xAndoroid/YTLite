#!/bin/sh
set -eu

unlock_file="Unlock521/Unlock.x"

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

grep -q '%hook YTPAPIHelper' "$unlock_file" &&
    fail 'Unlock.x must not hook YTPAPIHelper; YTLite 5.2.1 does not implement verifyAccessWithCompletion: there.'

grep -q 'verifyAccessWithCompletion:' "$unlock_file" &&
    fail 'Unlock.x must not patch verifyAccessWithCompletion:; YTLite 5.2.1 already hooks that selector to completion(YES).'

grep -q 'objc_getClass("YTPSettingsBuilder")' "$unlock_file" ||
    fail 'Unlock.x must patch YTPSettingsBuilder, where the Patreon settings gate lives.'

grep -q 'sel_registerName("rootTable")' "$unlock_file" ||
    fail 'Unlock.x must patch rootTable.'

grep -q 'sel_registerName("thanksTable")' "$unlock_file" ||
    fail 'Unlock.x must patch thanksTable, the logged-out/supporter table.'

grep -q 'sel_registerName("prefsTable")' "$unlock_file" ||
    fail 'Unlock.x must redirect locked settings tables to prefsTable.'

grep -q 'objc_getClass("DVNSupportersVC")' "$unlock_file" ||
    fail 'Unlock.x must retain a supporters-webview fallback.'

grep -q 'sel_registerName("viewDidLoad")' "$unlock_file" ||
    fail 'Unlock.x must disable DVNSupportersVC viewDidLoad as the fallback.'

grep -q 'class_getInstanceMethod' "$unlock_file" ||
    fail 'Unlock.x must patch Objective-C instance methods directly.'

grep -q 'method_setImplementation' "$unlock_file" ||
    fail 'Unlock.x must replace the matched selector implementation.'
