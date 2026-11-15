ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
BUILD ?= $(ROOT)build
SOURCES := $(wildcard $(ROOT)HKT*.m)
HEADERS := $(wildcard $(ROOT)*.h)
CFLAGS := -fobjc-arc -O2 -Wall -Werror -fvisibility=hidden -I$(ROOT)
FRAMEWORKS := -framework Foundation -framework UIKit -framework WebKit -framework CoreGraphics
TESTS := $(BUILD)/HackerTubeTests.app

.PHONY: all test-app
.DELETE_ON_ERROR:
all: $(BUILD)/HackerTube.dylib
test-app: $(TESTS)/HackerTubeTests

$(BUILD)/HackerTube.dylib: $(SOURCES) $(HEADERS)
	mkdir -p $(BUILD)
	xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 $(CFLAGS) -dynamiclib \
		-install_name @rpath/HackerTube.dylib $(FRAMEWORKS) $(SOURCES) -o $@

# SITE_URL points the Home replacement at the test host's own fixture server; leave it empty to
# run the same checks against the live site.
$(TESTS)/HackerTubeTests: $(SOURCES) $(HEADERS) $(ROOT)tests/host.m $(ROOT)tests/Info.plist $(ROOT)tests/fixture.html
	mkdir -p $(TESTS)
	cp $(ROOT)tests/Info.plist $(ROOT)tests/fixture.html $(TESTS)/
	xcrun --sdk iphonesimulator clang -arch $(shell uname -m) -mios-simulator-version-min=17.0 $(CFLAGS) \
		$(if $(SITE_URL),-DHKT_SITE_URL='"$(SITE_URL)"') $(FRAMEWORKS) $(SOURCES) $(ROOT)tests/host.m -o $@
	codesign --force --sign - $(TESTS)
