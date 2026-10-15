#import "NFContract.h"
#import "NFHTTP.h"
#import <Security/Security.h>

extern NSString *const NFChanged;
FOUNDATION_EXPORT BOOL NFVideoID(NSString *value);

@interface NFService : NSObject
@property(nonatomic, readonly) NFContract *contract;
@property(nonatomic, readonly) NSDictionary *settings;
@property(nonatomic, readonly) NSString *instructions;
@property(nonatomic, readonly) NSString *verdictNamespace;
+ (instancetype)shared;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults configuration:(NSURLSessionConfiguration *)configuration keyService:(NSString *)keyService;
- (BOOL)hasKey;
- (OSStatus)saveKey:(NSString *)key;
- (void)saveSettings:(NSDictionary *)settings;
- (void)saveInstructions:(NSString *)instructions;
- (void)clearVerdicts;
- (void)allow:(NSString *)videoID;
- (void)clearAllowed;
- (NSString *)reasonForVideo:(NSString *)videoID;
- (NSDictionary *)verdictForVideo:(NSString *)videoID;
- (void)judge:(NSString *)videoID;
// Retains the session token until replacement or close; the token must not retain a player/view.
- (void)openedVideo:(NSString *)videoID owner:(id)owner;
- (void)captions:(NSString *)text video:(NSString *)videoID owner:(id)owner;
@end
