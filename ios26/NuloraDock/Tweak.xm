#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

struct NDCoordinate { NSInteger row; NSInteger col; };
@interface SBDockView : UIView @end
@interface SBDockIconListView : UIView @end
static BOOL dockEnabled = YES;
static CGFloat radius = 32, opacity = 0.9;
static char panelKey, savedKey;
static NSHashTable *dockViews;
static BOOL NDStock(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return [name containsString:@"Background"] || [name containsString:@"Backdrop"] || [name containsString:@"Material"];
}
static void NDLayout(UIView *dock) {
    if (dock.bounds.size.width < 1 || dock.bounds.size.height < 1) return;
    UIVisualEffectView *panel = objc_getAssociatedObject(dock, &panelKey);
    if (!dockEnabled) {
        [panel removeFromSuperview]; objc_setAssociatedObject(dock, &panelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        for (UIView *child in dock.subviews) {
            NSNumber *saved = objc_getAssociatedObject(child, &savedKey);
            if (saved) { child.alpha = saved.doubleValue; objc_setAssociatedObject(child, &savedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        }
        return;
    }
    // iOS 12 releases use different backdrop classes. Do not silently abandon the dock if one ivar is absent.
    UIView *icons = nil;
    for (UIView *child in dock.subviews) {
        if (child == panel) continue;
        if ([NSStringFromClass(child.class) containsString:@"IconList"]) icons = child;
        if (NDStock(child)) {
            if (!objc_getAssociatedObject(child, &savedKey)) objc_setAssociatedObject(child, &savedKey, @(child.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            child.alpha = 0;
        }
    }
    if (!panel) {
        panel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleLight]];
        panel.userInteractionEnabled = NO; panel.accessibilityElementsHidden = YES;
        panel.layer.borderWidth = 0.75; panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.42].CGColor;
        panel.contentView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        panel.clipsToBounds = YES;
        objc_setAssociatedObject(dock, &panelKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (icons) [dock insertSubview:panel belowSubview:icons]; else [dock insertSubview:panel atIndex:0];
    }
    CGRect frame = CGRectInset(dock.bounds, 8, 6);
    if (frame.size.height > 110) { frame.origin.y = CGRectGetMaxY(frame) - 96; frame.size.height = 96; }
    panel.frame = frame; panel.layer.cornerRadius = MIN(radius, frame.size.height/2); panel.alpha = opacity;
}
static void NDReload(CFNotificationCenterRef c, void *o, CFStringRef n, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize(CFSTR("com.theipos.dock"));
        NSDictionary *v = CFBridgingRelease(CFPreferencesCopyMultiple(NULL, CFSTR("com.theipos.dock"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        dockEnabled = v[@"enabled"] ? [v[@"enabled"] boolValue] : YES;
        radius = v[@"radius"] ? MAX(12,MIN(44,[v[@"radius"] doubleValue])) : 32;
        opacity = v[@"opacity"] ? MAX(0.15,MIN(1,[v[@"opacity"] doubleValue])) : 0.9;
        for (UIView *dock in dockViews) [dock setNeedsLayout];
    });
}
%hook SBDockView
- (void)layoutSubviews { %orig; [dockViews addObject:self]; NDLayout(self); }
%end
%hook SBDockIconListView
+ (unsigned long long)maxIcons { return 5; }
- (unsigned long long)iconsInRowForSpacingCalculation { return 5; }
+ (unsigned long long)iconColumnsForInterfaceOrientation:(long long)orientation { return 5; }
- (CGPoint)originForIconAtCoordinate:(struct NDCoordinate)coordinate numberOfIcons:(unsigned long long)count {
    CGPoint native = %orig;
    if (count != 5 || coordinate.col < 1 || coordinate.col > 5 || self.bounds.size.width < 100) return native;
    struct NDCoordinate first = {coordinate.row,1}; CGPoint anchor = %orig(first,4);
    CGFloat width = self.bounds.size.width, cell = width/5;
    return CGPointMake((coordinate.col-0.5)*cell-30,anchor.y);
}
%end
%ctor {
    @autoreleasepool {
        if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 12) return;
        dockViews = [NSHashTable weakObjectsHashTable]; NDReload(NULL,NULL,NULL,NULL,NULL); %init;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,NDReload,CFSTR("com.theipos.dock/changed"),NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
