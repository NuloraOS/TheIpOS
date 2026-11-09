#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
@interface NDPrefsController : PSListController
@property(nonatomic,strong) NSArray *ndSpecifiers;
@end
@implementation NDPrefsController
- (NSArray *)specifiers {
    if (!self.ndSpecifiers) self.ndSpecifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return self.ndSpecifiers;
}
@end
