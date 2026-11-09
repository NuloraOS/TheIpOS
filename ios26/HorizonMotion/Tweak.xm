#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>

static BOOL enabled = YES, rendering = NO, homeEnabled = YES, appsEnabled = YES;
static CGFloat strength = 0.55;
static char driverKey, ghostKey;
static BOOL HMHome(void) { return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]; }
@interface HMGhostView : UIImageView @end
@implementation HMGhostView @end
@interface HMDriver : NSObject
@property(nonatomic,weak) UIWindow *window;
@property(nonatomic,strong) CADisplayLink *link;
@property(nonatomic) CFTimeInterval until;
@property(nonatomic) CGPoint direction;
- (void)tick:(CADisplayLink *)sender;
- (void)stop;
@end

static void HMReload(CFNotificationCenterRef c, void *o, CFStringRef n, const void *object, CFDictionaryRef info) {
    CFPreferencesAppSynchronize(CFSTR("com.theipos.motion"));
    NSDictionary *values = CFBridgingRelease(CFPreferencesCopyMultiple(NULL, CFSTR("com.theipos.motion"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    enabled = values[@"enabled"] ? [values[@"enabled"] boolValue] : YES;
    strength = values[@"strength"] ? MIN(1, MAX(0, [values[@"strength"] doubleValue])) : 0.55;
    homeEnabled = values[@"home"] ? [values[@"home"] boolValue] : YES;
    appsEnabled = values[@"apps"] ? [values[@"apps"] boolValue] : YES;
}
static BOOL HMAllowed(UIWindow *window) {
    if (!enabled || strength < 0.005 || rendering || !NSThread.isMainThread || !window || window.hidden || window.alpha < 0.1 || window.bounds.size.width < 1) return NO;
    UIApplication *app = UIApplication.sharedApplication;
    if (!app.protectedDataAvailable) return NO;
    if (HMHome()) return homeEnabled && window.windowLevel == UIWindowLevelNormal;
    return appsEnabled && app.applicationState == UIApplicationStateActive && window.isKeyWindow && window.windowLevel == UIWindowLevelNormal;
}
static void HMFrame(UIWindow *window, CGPoint direction) {
    if (!HMAllowed(window)) return;
    rendering = YES;
    @try {
        HMGhostView *old = objc_getAssociatedObject(window, &ghostKey);
        [old removeFromSuperview]; old.image = nil;
        CGFloat scale = MIN(0.5, 240.0 / window.bounds.size.width);
        UIGraphicsBeginImageContextWithOptions(window.bounds.size, NO, scale);
        CGContextRef drawing = UIGraphicsGetCurrentContext();
        if (drawing) [window.layer renderInContext:drawing];
        UIImage *snapshot = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        if (snapshot.CGImage) {
            static CIContext *context;
            static dispatch_once_t once;
            dispatch_once(&once, ^{ context = [CIContext contextWithOptions:@{kCIContextCacheIntermediates:@NO}]; });
            CIImage *input = [CIImage imageWithCGImage:snapshot.CGImage];
            CGFloat distance = hypot(direction.x, direction.y);
            // Actual directional convolution, not just a duplicated translucent frame.
            CIFilter *blur = [CIFilter filterWithName:@"CIMotionBlur"];
            [blur setValue:[input imageByClampingToExtent] forKey:kCIInputImageKey];
            [blur setValue:@((4 + strength * 24) * scale) forKey:kCIInputRadiusKey];
            [blur setValue:@(distance > 0.01 ? atan2(-direction.y, direction.x) : 0) forKey:kCIInputAngleKey];
            CIImage *output = [blur.outputImage imageByCroppingToRect:input.extent];
            CGImageRef image = output ? [context createCGImage:output fromRect:input.extent] : NULL;
            if (image) {
                HMGhostView *ghost = [[HMGhostView alloc] initWithImage:[UIImage imageWithCGImage:image]];
                CGImageRelease(image);
                ghost.frame = window.bounds; ghost.userInteractionEnabled = NO; ghost.accessibilityElementsHidden = YES;
                ghost.alpha = 0.20 + strength * 0.48;
                objc_setAssociatedObject(window, &ghostKey, ghost, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [window addSubview:ghost];
                [UIView animateWithDuration:0.10 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{ ghost.alpha = 0; } completion:^(BOOL done) {
                    [ghost removeFromSuperview]; ghost.image = nil;
                    if (objc_getAssociatedObject(window, &ghostKey) == ghost) objc_setAssociatedObject(window, &ghostKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }];
            }
        }
    } @catch (__unused NSException *e) { /* Preserve the underlying UI on unsupported surfaces. */ }
    rendering = NO;
}
@implementation HMDriver
- (void)tick:(CADisplayLink *)sender {
    if (CACurrentMediaTime() >= self.until || !HMAllowed(self.window)) { [self stop]; return; }
    HMFrame(self.window, self.direction);
}
- (void)stop {
    [self.link invalidate]; self.link = nil;
    HMGhostView *old = objc_getAssociatedObject(self.window, &ghostKey);
    [old removeFromSuperview]; old.image = nil;
    if (self.window) { objc_setAssociatedObject(self.window, &ghostKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); objc_setAssociatedObject(self.window, &driverKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
}
@end
static void HMBegin(UIWindow *window, CGPoint direction, CFTimeInterval duration) {
    if (!HMAllowed(window)) return;
    HMDriver *driver = objc_getAssociatedObject(window, &driverKey);
    if (!driver) {
        driver = [HMDriver new]; driver.window = window;
        objc_setAssociatedObject(window, &driverKey, driver, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        driver.link = [CADisplayLink displayLinkWithTarget:driver selector:@selector(tick:)];
        driver.link.preferredFramesPerSecond = 20;
        [driver.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    driver.direction = direction;
    driver.until = CACurrentMediaTime() + MIN(0.7, MAX(0.12, duration));
}
%hook UIScrollView
- (void)setContentOffset:(CGPoint)offset {
    CGPoint previous = self.contentOffset;
    %orig;
    if (self.dragging || self.decelerating) HMBegin(self.window, CGPointMake(offset.x - previous.x, offset.y - previous.y), 0.12);
}
- (void)setContentOffset:(CGPoint)offset animated:(BOOL)animated {
    CGPoint previous = self.contentOffset;
    %orig;
    if (animated) HMBegin(self.window, CGPointMake(offset.x - previous.x, offset.y - previous.y), 0.35);
}
%end
%hook CALayer
- (void)addAnimation:(CAAnimation *)animation forKey:(NSString *)key {
    %orig;
    if (!rendering && [animation isKindOfClass:[CAPropertyAnimation class]] && animation.duration >= 0.08 && animation.duration <= 1.5) {
        NSString *path = ((CAPropertyAnimation *)animation).keyPath;
        if ([path hasPrefix:@"position"] || [path hasPrefix:@"transform"] || [path hasPrefix:@"bounds"]) {
            id view = self.delegate;
            if ([view isKindOfClass:[UIView class]] && ![view isKindOfClass:[HMGhostView class]]) HMBegin(((UIView *)view).window, CGPointMake(1, 0), animation.duration);
        }
    }
}
%end
%ctor {
    @autoreleasepool {
        HMReload(NULL, NULL, NULL, NULL, NULL); %init;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, HMReload, CFSTR("com.theipos.motion/changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
