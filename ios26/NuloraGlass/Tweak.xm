#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface UIStatusBar : UIView @end
@interface _UIStatusBar : UIView @end
@interface NCNotificationShortLookView : UIView @end
@interface NGGlassPanel : UIVisualEffectView @end
@implementation NGGlassPanel @end
static BOOL on = YES, statusOn = YES, barsOn = YES, bannersOn = YES;
static CGFloat curvature = 18, opacity = 0.85;
static char panelKey, alphaKey;
static NSHashTable *surfaces;

static void NGStock(UIView *view, BOOL hide) {
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:NGGlassPanel.class]) continue;
        NSString *name = NSStringFromClass(child.class);
        if ([name containsString:@"BarBackground"] || [name containsString:@"NotificationBackground"]) {
            NSNumber *saved = objc_getAssociatedObject(child, &alphaKey);
            if (hide) {
                if (!saved) objc_setAssociatedObject(child, &alphaKey, @(child.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                child.alpha = 0;
            } else if (saved) {
                child.alpha = saved.doubleValue;
                objc_setAssociatedObject(child, &alphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
}
static void NGLayout(UIView *view, NSInteger kind) {
    if (!NSThread.isMainThread || view.bounds.size.width < 1 || view.bounds.size.height < 1) return;
    [surfaces addObject:view];
    NGGlassPanel *panel = objc_getAssociatedObject(view, &panelKey);
    BOOL active = on && (kind == 0 ? statusOn : kind == 1 ? barsOn : bannersOn);
    if (!active) {
        [panel removeFromSuperview]; objc_setAssociatedObject(view, &panelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (kind != 0) NGStock(view, NO);
        return;
    }
    BOOL dark = NO;
    if (kind == 0) dark = UIApplication.sharedApplication.statusBarStyle == UIStatusBarStyleLightContent;
    else if ([view isKindOfClass:UINavigationBar.class]) dark = ((UINavigationBar *)view).barStyle == UIBarStyleBlack;
    else if ([view isKindOfClass:UIToolbar.class]) dark = ((UIToolbar *)view).barStyle == UIBarStyleBlack;
    else if ([view isKindOfClass:UITabBar.class]) dark = ((UITabBar *)view).barStyle == UIBarStyleBlack;
    if (!panel) {
        panel = [[NGGlassPanel alloc] initWithEffect:nil];
        panel.userInteractionEnabled = NO; panel.accessibilityElementsHidden = YES;
        panel.layer.borderWidth = 0.5;
        panel.clipsToBounds = YES;
        objc_setAssociatedObject(view, &panelKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [view insertSubview:panel atIndex:0];
    }
    panel.effect = [UIBlurEffect effectWithStyle:dark ? UIBlurEffectStyleDark : UIBlurEffectStyleExtraLight];
    panel.contentView.backgroundColor = [UIColor colorWithWhite:dark ? 0 : 1 alpha:0.06];
    panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:dark ? 0.35 : 0.7].CGColor;
    CGFloat horizontalInset = kind == 0 ? 3 : 6, verticalInset = kind == 0 ? 1 : 3;
    panel.frame = CGRectInset(view.bounds, horizontalInset, verticalInset);
    panel.layer.cornerRadius = MIN(curvature, panel.bounds.size.height / 2);
    panel.alpha = opacity;
    // Keep the genuine clock, battery, buttons, text, accessibility and hit targets intact.
    if (kind != 0) NGStock(view, YES);
}
static void NGReload(CFNotificationCenterRef c, void *o, CFStringRef n, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize(CFSTR("com.theipos.glass"));
        NSDictionary *v = CFBridgingRelease(CFPreferencesCopyMultiple(NULL, CFSTR("com.theipos.glass"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        on = v[@"enabled"] ? [v[@"enabled"] boolValue] : YES;
        statusOn = v[@"status"] ? [v[@"status"] boolValue] : YES;
        barsOn = v[@"bars"] ? [v[@"bars"] boolValue] : YES;
        bannersOn = v[@"banners"] ? [v[@"banners"] boolValue] : YES;
        curvature = v[@"radius"] ? MAX(6, MIN(32, [v[@"radius"] doubleValue])) : 18;
        opacity = v[@"opacity"] ? MAX(0.25, MIN(1, [v[@"opacity"] doubleValue])) : 0.85;
        for (UIView *view in surfaces) [view setNeedsLayout];
    });
}
%hook UINavigationBar
- (void)layoutSubviews { %orig; NGLayout(self, 1); }
%end
%hook UIToolbar
- (void)layoutSubviews { %orig; NGLayout(self, 1); }
%end
%hook UITabBar
- (void)layoutSubviews { %orig; NGLayout(self, 1); }
%end
%hook UIStatusBar
- (void)layoutSubviews { %orig; NGLayout(self, 0); }
%end
%hook _UIStatusBar
- (void)layoutSubviews { %orig; NGLayout(self, 0); }
%end
%hook NCNotificationShortLookView
- (void)layoutSubviews { %orig; NGLayout(self, 2); }
%end
%ctor {
    @autoreleasepool {
        if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 12) return;
        surfaces = [NSHashTable weakObjectsHashTable]; NGReload(NULL, NULL, NULL, NULL, NULL); %init;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NGReload, CFSTR("com.theipos.glass/changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
