#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

@interface NFContract : NSObject
@property(nonatomic, readonly) NSDictionary *categories;
@property(nonatomic, readonly) NSArray<NSString *> *categoryNames;
@property(nonatomic, readonly) NSDictionary *defaults;
@property(nonatomic, readonly) NSDictionary *limits;
@property(nonatomic, readonly) NSArray<NSString *> *strictnessNames;
@property(nonatomic, readonly) NSString *endpoint;
- (id)call:(NSString *)function arguments:(NSArray *)arguments;
- (NSString *)guidance:(NSString *)text;
- (NSString *)namespaceForGuidance:(NSString *)text;
- (NSString *)reason:(NSDictionary *)verdict settings:(NSDictionary *)settings;
@end
