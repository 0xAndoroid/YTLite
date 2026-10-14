#import "NFContract.h"
#import <CommonCrypto/CommonDigest.h>
#include "NFContract.inc"

@implementation NFContract {
    JSContext *_context;
    JSValue *_contract;
}
- (instancetype)init {
    if ((self = [super init])) {
        _context = [JSContext new];
        _contract = [_context evaluateScript:@(NFContractSource)];
        if (_context.exception || ![self guidance:@""]) return nil;
    }
    return self;
}
- (id)call:(NSString *)function arguments:(NSArray *)arguments {
    _context.exception = nil;
    JSValue *value = [_contract[function] callWithArguments:arguments];
    return _context.exception || value.isUndefined || value.isNull ? nil : value.toObject;
}
- (NSDictionary *)categories { return [_contract[@"CATEGORIES"] toDictionary]; }
- (NSArray *)categoryNames { return [_contract[@"categoryNames"] toArray]; }
- (NSDictionary *)defaults { return [_contract[@"DEFAULT_SETTINGS"] toDictionary]; }
- (NSDictionary *)limits { return [_contract[@"LIMITS"] toDictionary]; }
- (NSArray *)strictnessNames {
    NSDictionary *values = [_contract[@"STRICTNESS"] toDictionary];
    return [values.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return [values[b] compare:values[a]]; }];
}
- (NSString *)endpoint { return [_contract[@"DECISIONS_URL"] toString]; }
- (NSString *)guidance:(NSString *)text {
    return [self call:@"effectiveGuidance" arguments:@[text ?: @""]];
}
- (NSString *)namespaceForGuidance:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *name = [NSMutableString stringWithCapacity:16];
    for (NSUInteger i = 0; i < 8; i++) [name appendFormat:@"%02x", digest[i]];
    return name;
}
- (NSString *)reason:(NSDictionary *)verdict settings:(NSDictionary *)settings {
    double threshold = [_contract[@"STRICTNESS"][settings[@"strictness"]] toDouble];
    NSDictionary *judged = [_contract[@"JUDGED"] toDictionary];
    for (NSString *name in [_contract[@"judgedNames"] toArray]) {
        if (![name isEqualToString:@"custom_instructions"] && ![settings[@"categories"][name] boolValue]) continue;
        if ([verdict[@"scores"][name] doubleValue] < threshold) continue;
        id code = verdict[@"reasons"][name];
        if ([code isKindOfClass:NSString.class]) return judged[name][@"reasons"][code][@"label"];
    }
    return nil;
}
@end
