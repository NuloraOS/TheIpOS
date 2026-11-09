#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

typedef struct { NSInteger row; NSInteger col; } NDCoordinate;
@interface SBDockView : UIView @end
@interface SBDockIconListView : UIView @end
static BOOL dockEnabled = YES;
static CGFloat radius = 30, opacity = 0.85;
static char panelKey, savedKey;
static NSHashTable *dockViews;
static UIView *NDBackground(UIView *dock) {
    Ivar field = class_getInstanceVariable(dock.class, "_backgroundView");
    id value = field ? object_getIvar(dock, field) : nil;
    return [value isKindOfClass:UIView.class] ? value : nil;
}
static void NDLayout(UIView *dock) {
    UIView *stock = NDBackground(dock);
    UIVisualEffectView *panel = objc_getAssociatedObject(dock, &panelKey);
    if (!dockEnabled) {
        [panel removeFromSuperview]; objc_setAssociatedObject(dock, &panelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSNumber *saved = objc_getAssociatedObject(dock, &savedKey);
        if (stock && saved) stock.alpha = saved.doubleValue;
        return;
    }
    // Avoid adding an opaque duplicate when an OS variant has no recognised backdrop.
    if (!stock) return;
    if (!objc_getAssociatedObject(dock, &savedKey)) objc_setAssociatedObject(dock, &savedKey, @(stock.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    stock.alpha = 0;
    if (!panel) {
        panel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleLight]];
        panel.userInteractionEnabled = NO; panel.accessibilityElementsHidden = YES;
        panel.layer.borderWidth = 0.5; panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
        objc_setAssociatedObject(dock, &panelKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [dock insertSubview:panel atIndex:0];
    }
    panel.frame = CGRectInset(dock.bounds, 8, 7);
    panel.layer.cornerRadius = MIN(radius, panel.bounds.size.height / 2);
    panel.clipsToBounds = YES; panel.alpha = opacity;
}
static void NDReload(CFNotificationCenterRef c, void *o, CFStringRef n, const void *object, CFDictionaryRef info) {
    CFPreferencesAppSynchronize(CFSTR("com.theipos.dock"));
    NSDictionary *values = CFBridgingRelease(CFPreferencesCopyMultiple(NULL, CFSTR("com.theipos.dock"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    dockEnabled = values[@"enabled"] ? [values[@"enabled"] boolValue] : YES;
    radius = values[@"radius"] ? MAX(12, MIN(44, [values[@"radius"] doubleValue])) : 30;
    opacity = values[@"opacity"] ? MAX(0.15, MIN(1, [values[@"opacity"] doubleValue])) : 0.85;
    dispatch_async(dispatch_get_main_queue(), ^{ for (UIView *dock in dockViews) [dock setNeedsLayout]; });
}
%hook SBDockView
- (void)layoutSubviews { %orig; [dockViews addObject:self]; NDLayout(self); }
%end
%hook SBDockIconListView
+ (unsigned long long)maxIcons { return 5; }
- (unsigned long long)iconsInRowForSpacingCalculation { return 5; }
+ (unsigned long long)iconColumnsForInterfaceOrientation:(long long)orientation { return 5; }
- (CGPoint)originForIconAtCoordinate:(NDCoordinate)coordinate numberOfIcons:(unsigned long long)count {
    CGPoint native = %orig;
    if (count != 5 || coordinate.col < 1 || coordinate.col > 5) return native;
    // Keep native vertical positioning. Distribute real icon cells across the available width.
    NDCoordinate first = {coordinate.row, 1};
    CGPoint anchor = %orig(first, 4);
    CGFloat iconWidth = 60, width = self.bounds.size.width;
    if (width < 5 * iconWidth) return native;
    CGFloat gap = (width - 5 * iconWidth) / 6;
    return CGPointMake(gap + (coordinate.col - 1) * (iconWidth + gap), anchor.y);
}
%end
%ctor {
    @autoreleasepool {
        if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 12) return;
        dockViews = [NSHashTable weakObjectsHashTable];
        NDReload(NULL, NULL, NULL, NULL, NULL); %init;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NDReload, CFSTR("com.theipos.dock/changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
