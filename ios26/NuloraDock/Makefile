ARCHS = arm64
TARGET = iphone:clang:latest:12.0
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = NuloraDock
NuloraDock_FILES = Tweak.xm
NuloraDock_FRAMEWORKS = UIKit QuartzCore
NuloraDock_CFLAGS = -fobjc-arc
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
