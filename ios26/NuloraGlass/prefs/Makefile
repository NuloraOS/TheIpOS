ARCHS = arm64
TARGET = iphone:clang:latest:12.0
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = NuloraGlassPrefs
NuloraGlassPrefs_FILES = NGPrefsController.m
NuloraGlassPrefs_FRAMEWORKS = UIKit
NuloraGlassPrefs_PRIVATE_FRAMEWORKS = Preferences
NuloraGlassPrefs_LDFLAGS = -F$(THEOS_PROJECT_DIR)/../HorizonMotion/prefs/stubs
NuloraGlassPrefs_INSTALL_PATH = /Library/PreferenceBundles
NuloraGlassPrefs_CFLAGS = -fobjc-arc
include $(THEOS_MAKE_PATH)/bundle.mk
