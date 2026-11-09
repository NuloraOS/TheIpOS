#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
@interface HMPrefsController : PSListController
@property(nonatomic,strong) NSArray *hmSpecifiers;
@end
@implementation HMPrefsController
- (NSArray *)specifiers {
    if (!self.hmSpecifiers) self.hmSpecifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return self.hmSpecifiers;
}
@end
