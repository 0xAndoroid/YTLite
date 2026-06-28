THEOS_PACKAGE_SCHEME = rootless

ARCHS = arm64
TARGET := iphone:clang:16.5:13.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YTLiteUnlock
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation
$(TWEAK_NAME)_CFLAGS = -fobjc-arc
$(TWEAK_NAME)_FILES = Unlock.x

include $(THEOS_MAKE_PATH)/tweak.mk
