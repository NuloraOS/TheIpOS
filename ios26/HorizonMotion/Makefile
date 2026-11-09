ARCHS = arm64
TARGET = iphone:clang:latest:12.0
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = HorizonMotion
HorizonMotion_FILES = Tweak.xm
HorizonMotion_FRAMEWORKS = UIKit QuartzCore CoreImage
HorizonMotion_CFLAGS = -fobjc-arc
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
