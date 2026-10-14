ARCHS = arm64
TARGET := iphone:clang:16.5:17.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NoiseFilter
NoiseFilter_FRAMEWORKS = Foundation JavaScriptCore Security
NoiseFilter_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/.theos
NoiseFilter_FILES = NFContract.m NFHTTP.m NFService.m

before-all::
	node bundle.mjs $(THEOS_PROJECT_DIR)/.theos/NFContract.inc

include $(THEOS_MAKE_PATH)/tweak.mk
