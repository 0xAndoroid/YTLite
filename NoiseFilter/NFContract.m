#import "NFContract.h"
#import <CommonCrypto/CommonDigest.h>
#include <math.h>
#include "NFContract.inc"

@implementation NFContract {
    JSContext *_context;
    JSValue *_contract;
    NSDictionary *_judged, *_thresholds;
    NSArray *_judgedNames;
}
- (instancetype)init {
    if ((self = [super init])) {
        _context = [JSContext new];
        _contract = [_context evaluateScript:@(NFContractSource)];
        if (_context.exception || ![self guidance:@""]) return nil;
        _categories = [[_contract[@"CATEGORIES"] toDictionary] copy];
        _categoryNames = [[_contract[@"categoryNames"] toArray] copy];
        _defaults = [[_contract[@"DEFAULT_SETTINGS"] toDictionary] copy];
        _limits = [[_contract[@"LIMITS"] toDictionary] copy];
        _endpoint = [[_contract[@"DECISIONS_URL"] toString] copy];
        _judged = [[_contract[@"JUDGED"] toDictionary] copy];
        _judgedNames = [[_contract[@"judgedNames"] toArray] copy];
        _thresholds = [[_contract[@"STRICTNESS"] toDictionary] copy];
        _strictnessNames = [_thresholds.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return [self->_thresholds[b] compare:self->_thresholds[a]]; }];
    }
    return self;
}
- (id)call:(NSString *)function arguments:(NSArray *)arguments {
    _context.exception = nil;
    JSValue *value = [_contract[function] callWithArguments:arguments];
    return _context.exception || value.isUndefined || value.isNull ? nil : value.toObject;
}
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
    NSNumber *selected = _thresholds[settings[@"strictness"] ?: @""];
    double threshold = selected ? selected.doubleValue : NAN;
    for (NSString *name in _judgedNames) {
        if (![name isEqualToString:@"custom_instructions"] && ![settings[@"categories"][name] boolValue]) continue;
        if (!([verdict[@"scores"][name] doubleValue] >= threshold)) continue;
        id code = verdict[@"reasons"][name];
        if ([code isKindOfClass:NSString.class]) return _judged[name][@"reasons"][code][@"label"];
    }
    return nil;
}
@end
