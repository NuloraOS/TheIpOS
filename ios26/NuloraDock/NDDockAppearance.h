#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

struct NDCoordinate { NSInteger row; NSInteger col; };
@interface SBDockView : UIView @end
@interface SBDockIconListView : UIView @end
static BOOL dockEnabled = YES;
static CGFloat radius = 32, opacity = 0.9;
static char panelKey, savedKey, targetsKey;
static NSHashTable *dockViews;
static BOOL NDStock(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return [name containsString:@"Background"] || [name containsString:@"Backdrop"] || [name containsString:@"Material"] || [name containsString:@"WallpaperEffect"];
}
static UIView *NDViewIvar(UIView *dock, const char *name) {
    Ivar slot = class_getInstanceVariable(dock.class, name);
    if (!slot || ivar_getTypeEncoding(slot)[0] != '@') return nil;
    id value = object_getIvar(dock, slot);
    return [value isKindOfClass:UIView.class] ? value : nil;
}
static void NDHide(UIView *dock, UIView *target, UIView *panel, UIView *icons) {
    if (!target || target == dock || target == panel || target == icons || (icons && [icons isDescendantOfView:target])) return;
    NSMutableArray *targets = objc_getAssociatedObject(dock, &targetsKey);
    if (!targets) { targets = [NSMutableArray array]; objc_setAssociatedObject(dock, &targetsKey, targets, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    if (!objc_getAssociatedObject(target, &savedKey)) {
        objc_setAssociatedObject(target, &savedKey, @{@"alpha":@(target.alpha), @"hidden":@(target.hidden)}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [targets addObject:target];
    }
    target.hidden = YES; target.alpha = 0;
}
static void NDLayout(UIView *dock) {
    if (dock.bounds.size.width < 1 || dock.bounds.size.height < 1) return;
    UIVisualEffectView *panel = objc_getAssociatedObject(dock, &panelKey);
    if (!dockEnabled) {
        [panel removeFromSuperview]; objc_setAssociatedObject(dock, &panelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        for (UIView *child in objc_getAssociatedObject(dock, &targetsKey)) {
            NSDictionary *saved = objc_getAssociatedObject(child, &savedKey);
            if (saved) { child.alpha = [saved[@"alpha"] doubleValue]; child.hidden = [saved[@"hidden"] boolValue]; objc_setAssociatedObject(child, &savedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        }
        objc_setAssociatedObject(dock, &targetsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    // iOS 12 releases use different backdrop classes. Do not silently abandon the dock if one ivar is absent.
    UIView *icons = nil;
    for (UIView *child in dock.subviews) {
        if (child == panel) continue;
        if ([NSStringFromClass(child.class) containsString:@"IconList"]) icons = child;
    }
    // iOS 12's SBWallpaperEffectView (and plain UIImageView variants) do not contain "Background" in their class names.
    for (NSString *name in @[@"_backgroundView", @"_backgroundEffectView", @"_wallpaperEffectView"]) NDHide(dock, NDViewIvar(dock,name.UTF8String), panel, icons);
    for (UIView *child in dock.subviews) if (NDStock(child)) NDHide(dock, child, panel, icons);
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
