ARCHS = arm64
TARGET = iphone:clang:latest:12.0
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = NuloraDockPrefs
NuloraDockPrefs_FILES = NDPrefsController.m
NuloraDockPrefs_FRAMEWORKS = UIKit
NuloraDockPrefs_PRIVATE_FRAMEWORKS = Preferences
NuloraDockPrefs_LDFLAGS = -F$(THEOS_PROJECT_DIR)/../HorizonMotion/prefs/stubs
NuloraDockPrefs_INSTALL_PATH = /Library/PreferenceBundles
NuloraDockPrefs_CFLAGS = -fobjc-arc
include $(THEOS_MAKE_PATH)/bundle.mk
