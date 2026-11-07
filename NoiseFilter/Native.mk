ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
BUILD ?= $(TMPDIR)/noise-filter-build
SOURCES := $(wildcard $(ROOT)NF*.m)
HEADERS := $(wildcard $(ROOT)NF*.h)
CFLAGS := -fobjc-arc -O2 -Wall -Werror -I$(ROOT) -I$(BUILD)
FRAMEWORKS := -framework Foundation -framework UIKit -framework JavaScriptCore -framework Security -framework CoreGraphics

.PHONY: all uikit-app FORCE
.DELETE_ON_ERROR:
all: $(BUILD)/NoiseFilter.dylib
uikit-app: $(BUILD)/NoiseFilterTests.app/noise-filter-tests

$(BUILD)/NFContract.inc: $(ROOT)verdict.js $(ROOT)bundle.mjs FORCE
	mkdir -p $(BUILD)
	node $(ROOT)bundle.mjs $@

$(BUILD)/NoiseFilter.dylib: $(SOURCES) $(HEADERS) $(BUILD)/NFContract.inc
	xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 $(CFLAGS) -dynamiclib -install_name @rpath/NoiseFilter.dylib $(FRAMEWORKS) $(SOURCES) -o $@

$(BUILD)/NoiseFilterTests.app/noise-filter-tests: $(SOURCES) $(HEADERS) $(ROOT)tests/uikit.m $(ROOT)tests/Info.plist $(BUILD)/NFContract.inc
	mkdir -p $(BUILD)/NoiseFilterTests.app
	cp $(ROOT)tests/Info.plist $(BUILD)/NoiseFilterTests.app/Info.plist
	xcrun --sdk iphonesimulator clang -arch $(shell uname -m) -mios-simulator-version-min=17.0 $(CFLAGS) -DNF_TESTING=1 $(FRAMEWORKS) $(SOURCES) $(ROOT)tests/uikit.m -o $@
	codesign --force --sign - $(BUILD)/NoiseFilterTests.app

FORCE:
