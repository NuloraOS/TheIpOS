#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
@interface NGPrefsController : PSListController
@property(nonatomic,strong) NSArray *ngSpecifiers;
@end
@implementation NGPrefsController
- (NSArray *)specifiers {
    if (!self.ngSpecifiers) self.ngSpecifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return self.ngSpecifiers;
}
@end
