#import "NFContract.h"
#import "NFHTTP.h"
#import <Security/Security.h>

extern NSString *const NFChanged;
BOOL NFVideoID(NSString *value);

@interface NFService : NSObject
@property(nonatomic, readonly) NFContract *contract;
@property(nonatomic, readonly) NSDictionary *settings;
@property(nonatomic, readonly) NSString *instructions;
@property(nonatomic, readonly) NSString *namespace;
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
- (void)openedVideo:(NSString *)videoID owner:(id)owner;
- (void)captions:(NSString *)text video:(NSString *)videoID owner:(id)owner;
@end
