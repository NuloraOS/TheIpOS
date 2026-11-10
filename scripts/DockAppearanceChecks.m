#import "../ios26/NuloraDock/NDDockAppearance.h"
#import "DockAppearanceChecks.h"
#import <math.h>
@interface NDLegacyDockFixture : UIView { @public UIView *_backgroundView; } @end
@implementation NDLegacyDockFixture @end
@interface NDFixtureIconList : UIView @end
@implementation NDFixtureIconList @end

const char *NDDockRunChecks(void) {
    static NSString *report;
    NSMutableArray *errors = [NSMutableArray array];
    NDLegacyDockFixture *dock = [[NDLegacyDockFixture alloc] initWithFrame:CGRectMake(0,0,320,104)];
    dock->_backgroundView = [[UIView alloc] initWithFrame:dock.bounds];
    dock->_backgroundView.alpha = 0.64;
    [dock addSubview:dock->_backgroundView];
    UIView *icons = [[NDFixtureIconList alloc] initWithFrame:dock.bounds]; [dock addSubview:icons];
    dockEnabled = YES; NDLayout(dock);
    UIView *panel = objc_getAssociatedObject(dock,&panelKey);
    if (!dock->_backgroundView.hidden || dock->_backgroundView.alpha != 0) [errors addObject:@"native ivar background remains visible"];
    if (!panel || panel.superview != dock || panel.hidden) [errors addObject:@"replacement panel missing"];
    if (icons.hidden || icons.alpha != 1) [errors addObject:@"icons were hidden"];
    dock->_backgroundView.hidden = NO; dock->_backgroundView.alpha = 1; NDLayout(dock);
    if (!dock->_backgroundView.hidden || objc_getAssociatedObject(dock,&panelKey) != panel) [errors addObject:@"layout does not retain exactly one replacement"];
    dockEnabled = NO; NDLayout(dock);
    if (dock->_backgroundView.hidden || fabs(dock->_backgroundView.alpha-0.64)>0.0001 || objc_getAssociatedObject(dock,&panelKey)) [errors addObject:@"disabled state did not restore native backdrop"];
    dockEnabled = YES;
    report = errors.count ? [@"FAIL " stringByAppendingString:[errors componentsJoinedByString:@"; "]] : @"PASS stock backdrop hidden, icon list visible, one panel, native appearance restored on disable; UIKit fixture only";
    return report.UTF8String;
}
