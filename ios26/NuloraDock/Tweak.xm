#import "NDDockAppearance.h"
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
- (void)didMoveToWindow { %orig; [dockViews addObject:self]; NDLayout(self); }
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
