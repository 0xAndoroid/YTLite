#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

@interface NFContract : NSObject
@property(nonatomic, readonly) NSDictionary *categories;
@property(nonatomic, readonly) NSArray<NSString *> *categoryNames;
@property(nonatomic, readonly) NSDictionary *defaults;
@property(nonatomic, readonly) NSDictionary *limits;
@property(nonatomic, readonly) NSArray<NSString *> *strictnessNames;
@property(nonatomic, readonly) NSString *endpoint;
@property(nonatomic, readonly) NSString *revision;
- (id)call:(NSString *)function arguments:(NSArray *)arguments;
- (NSString *)guidance:(NSString *)text;
- (NSString *)namespaceForGuidance:(NSString *)text model:(NSString *)model;
- (NSDictionary *)settingsWithDefaults:(NSDictionary *)stored;
- (NSDictionary *)settingsOverrides:(NSDictionary *)settings;
- (NSString *)reason:(NSDictionary *)verdict settings:(NSDictionary *)settings;
@end
