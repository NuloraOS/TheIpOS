#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
@interface HMPrefsController : PSListController @end
@implementation HMPrefsController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
@end
