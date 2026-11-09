ARCHS = arm64
TARGET = iphone:clang:latest:12.0
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = HorizonMotionPrefs
HorizonMotionPrefs_FILES = HMPrefsController.m
HorizonMotionPrefs_FRAMEWORKS = UIKit
HorizonMotionPrefs_PRIVATE_FRAMEWORKS = Preferences
HorizonMotionPrefs_LDFLAGS = -F$(THEOS_PROJECT_DIR)/prefs/stubs
HorizonMotionPrefs_INSTALL_PATH = /Library/PreferenceBundles
HorizonMotionPrefs_CFLAGS = -fobjc-arc
include $(THEOS_MAKE_PATH)/bundle.mk
