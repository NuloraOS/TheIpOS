#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static BOOL enabled = YES, rendering = NO;
static CGFloat strength = 0.18;
static CFTimeInterval lastFrame = 0;
static char ghostKey;
@interface HMGhostView : UIImageView @end
@implementation HMGhostView @end

static void HMReload(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    CFPreferencesAppSynchronize(CFSTR("com.neotech.horizonmotion"));
    CFPropertyListRef on = CFPreferencesCopyAppValue(CFSTR("enabled"), CFSTR("com.neotech.horizonmotion"));
    CFPropertyListRef amount = CFPreferencesCopyAppValue(CFSTR("strength"), CFSTR("com.neotech.horizonmotion"));
    enabled = on ? [(__bridge id)on boolValue] : YES;
    strength = amount ? MIN(0.35, MAX(0, [(__bridge id)amount doubleValue])) : 0.18;
    if (on) CFRelease(on); if (amount) CFRelease(amount);
}

static void HMTrail(UIWindow *window, CGPoint direction) {
    if (!enabled || strength < 0.005 || rendering || !NSThread.isMainThread || !window.isKeyWindow || window.hidden || window.windowLevel != UIWindowLevelNormal) return;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - lastFrame < 0.11 || window.bounds.size.width < 1) return;
    lastFrame = now; rendering = YES;
    @try {
        HMGhostView *old = objc_getAssociatedObject(window, &ghostKey);
        [old removeFromSuperview]; old.image = nil;
        // Bounded low-resolution, in-memory snapshot. No files, screen recording or network.
        CGFloat scale = MIN(0.5, 200.0 / window.bounds.size.width);
        UIGraphicsBeginImageContextWithOptions(window.bounds.size, NO, scale);
        CGContextRef context = UIGraphicsGetCurrentContext();
        if (context) [window.layer renderInContext:context];
        UIImage *snapshot = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
        if (snapshot) {
            HMGhostView *ghost = [[HMGhostView alloc] initWithImage:snapshot]; ghost.frame = window.bounds;
            ghost.userInteractionEnabled = NO; ghost.accessibilityElementsHidden = YES; ghost.alpha = strength;
            objc_setAssociatedObject(window, &ghostKey, ghost, OBJC_ASSOCIATION_RETAIN_NONATOMIC); [window addSubview:ghost];
            CGFloat dx = MAX(-10, MIN(10, direction.x)), dy = MAX(-10, MIN(10, direction.y));
            [UIView animateWithDuration:0.065 + strength * 0.12 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
                ghost.alpha = 0; ghost.transform = CGAffineTransformMakeTranslation(dx, dy);
            } completion:^(BOOL finished) {
                [ghost removeFromSuperview]; ghost.image = nil;
                if (objc_getAssociatedObject(window, &ghostKey) == ghost) objc_setAssociatedObject(window, &ghostKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }];
        }
    } @catch (__unused NSException *error) { /* An unavailable surface leaves the original animation intact. */ }
    rendering = NO;
}

%hook UIScrollView
- (void)setContentOffset:(CGPoint)offset {
    CGPoint old = self.contentOffset;
    if (self.dragging || self.decelerating) HMTrail(self.window, CGPointMake((old.x - offset.x) * 0.15, (old.y - offset.y) * 0.15));
    %orig;
}
%end

%hook CALayer
- (void)addAnimation:(CAAnimation *)animation forKey:(NSString *)key {
    if (!rendering && ![self.delegate isKindOfClass:[HMGhostView class]] && [animation isKindOfClass:[CABasicAnimation class]] && animation.duration >= 0.08 && animation.duration <= 1.2) {
        NSString *path = ((CABasicAnimation *)animation).keyPath;
        if ([path hasPrefix:@"position"] || [path hasPrefix:@"transform"] || [path hasPrefix:@"bounds"]) {
            id delegate = self.delegate;
            if ([delegate isKindOfClass:[UIView class]]) HMTrail(((UIView *)delegate).window, CGPointZero);
        }
    }
    %orig;
}
%end

%ctor {
    @autoreleasepool {
        HMReload(NULL, NULL, NULL, NULL, NULL);
        %init;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, HMReload, CFSTR("com.neotech.horizonmotion/changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
