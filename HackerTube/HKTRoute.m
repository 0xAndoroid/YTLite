#import "HKTRoute.h"

static BOOL IsVideoID(NSString *value) {
    static NSCharacterSet *invalid;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        invalid = [NSCharacterSet characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"].invertedSet;
    });
    return value.length == 11 && [value rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

static NSInteger Port(NSURL *url) {
    if (url.port) return url.port.integerValue;
    return [url.scheme.lowercaseString isEqual:@"https"] ? 443 : 80;
}

static BOOL SameOrigin(NSURL *a, NSURL *b) {
    return [a.scheme.lowercaseString isEqual:b.scheme.lowercaseString]
        && [a.host.lowercaseString isEqual:b.host.lowercaseString] && Port(a) == Port(b);
}

HKTRoute HKTRouteForURL(NSURL *url, NSURL *home, NSString **videoID) {
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqual:@"https"] && ![scheme isEqual:@"http"]) return HKTRouteBlocked;
    NSString *candidate;
    if (SameOrigin(url, home)) {
        NSArray<NSString *> *parts = url.pathComponents;
        if (parts.count < 2 || ![parts[1] isEqual:@"watch"]) return HKTRouteInSite;
        if (parts.count == 3) candidate = parts[2];
    } else if ([@[@"youtube.com", @"www.youtube.com", @"m.youtube.com"] containsObject:url.host.lowercaseString]
               && [url.path isEqual:@"/watch"]) {
        for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
            if ([item.name isEqual:@"v"]) candidate = item.value;
        }
    } else {
        return HKTRouteExternal;
    }
    if (!IsVideoID(candidate)) return HKTRouteBlocked;
    if (videoID) *videoID = candidate;
    return HKTRouteVideo;
}
