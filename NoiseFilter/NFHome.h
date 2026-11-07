#import <Foundation/Foundation.h>
@class NFService;

BOOL NFInstallHomeHooks(NFService *service);
NSDictionary *NFHomeDiagnostics(void);
BOOL NFCaptureHome(NFService *service, NSError **error);
