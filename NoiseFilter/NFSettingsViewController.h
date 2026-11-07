#import <UIKit/UIKit.h>
@class NFService;

BOOL NFInstallSettingsHooks(NFService *service);

@interface NFSettingsViewController : UITableViewController
- (instancetype)initWithService:(NFService *)service;
@end
