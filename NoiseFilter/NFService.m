#import "NFService.h"
#import <TargetConditionals.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#endif

NSString *const NFChanged = @"NFChanged";
BOOL NFVideoID(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length != 11) return NO;
    NSCharacterSet *valid = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"];
    return [value rangeOfCharacterFromSet:valid.invertedSet].location == NSNotFound;
}

@interface NFJob : NSObject
@property(nonatomic, copy) NSString *videoID, *guidance, *cacheKey, *identity, *transcript;
@property(nonatomic, copy) NSDictionary *settings;
@property(nonatomic, copy) NSString *requestID;
@property(nonatomic) NSUInteger generation;
@end
@implementation NFJob
@end

@implementation NFService {
    NSUserDefaults *_store;
    NFHTTP *_http;
    NSString *_keyService;
    NSMutableDictionary<NSString *, NFJob *> *_jobs;
    NSMutableArray<NFJob *> *_queue;
    NSUInteger _active, _generation;
    NSTimeInterval _backoff;
    NSString *_openedVideo, *_captionText;
    id _captionOwner;
    BOOL _hasKey;
    NSString *_lastError;
}
+ (instancetype)shared {
    if (!NSThread.isMainThread) return nil;
#if TARGET_OS_IOS
    if (!UIApplication.sharedApplication.protectedDataAvailable) return nil;
#endif
    static NFService *service;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        service = [[self alloc] initWithDefaults:[[NSUserDefaults alloc] initWithSuiteName:@"com.andoroid.youtube-noise-filter"] configuration:NSURLSessionConfiguration.ephemeralSessionConfiguration keyService:@"com.andoroid.youtube-noise-filter"];
    });
    return service;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults configuration:(NSURLSessionConfiguration *)configuration keyService:(NSString *)keyService {
    if ((self = [super init])) {
        _store = defaults;
        _keyService = [keyService copy];
        _contract = [NFContract new];
        if (!_contract) return nil;
        _http = [[NFHTTP alloc] initWithConfiguration:configuration];
        _jobs = [NSMutableDictionary new];
        _queue = [NSMutableArray new];
        _instructions = [_contract guidance:[_store stringForKey:@"instructions"]];
        _verdictNamespace = [_contract namespaceForGuidance:_instructions model:self.settings[@"model"]];
        _keychainStatus = SecItemCopyMatching((__bridge CFDictionaryRef)self.keyQuery, NULL);
        _hasKey = _keychainStatus != errSecItemNotFound;
    }
    return self;
}
- (void)dealloc { [_http invalidate]; }
- (NSDictionary *)keyQuery {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: _keyService, (__bridge id)kSecAttrAccount: @"typesafe-api-key"};
}
- (NSString *)key {
    NSMutableDictionary *query = [self.keyQuery mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef value = NULL;
    _keychainStatus = SecItemCopyMatching((__bridge CFDictionaryRef)query, &value);
    if (_keychainStatus != errSecSuccess) return nil;
    NSString *key = [[NSString alloc] initWithData:CFBridgingRelease(value) encoding:NSUTF8StringEncoding];
    if (!key.length) _keychainStatus = errSecDecode;
    return key;
}
- (BOOL)hasKey { return _hasKey; }
- (BOOL)enabled { return [self.settings[@"sites"][@"youtube"] boolValue]; }
- (OSStatus)saveKey:(NSString *)key {
    key = [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    OSStatus status;
    if (!key.length) {
        status = SecItemDelete((__bridge CFDictionaryRef)self.keyQuery);
        if (status == errSecItemNotFound) status = errSecSuccess;
    } else {
        NSData *bytes = [key dataUsingEncoding:NSUTF8StringEncoding];
        if (!bytes) return errSecParam;
        NSDictionary *value = @{(__bridge id)kSecValueData: bytes,
                               (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly};
        status = SecItemUpdate((__bridge CFDictionaryRef)self.keyQuery, (__bridge CFDictionaryRef)value);
        if (status == errSecItemNotFound) {
            NSMutableDictionary *item = [self.keyQuery mutableCopy];
            [item addEntriesFromDictionary:value];
            status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
        }
    }
    if (status == errSecSuccess) {
        _hasKey = key.length > 0;
        _keychainStatus = _hasKey ? errSecSuccess : errSecItemNotFound;
        _keyRejected = NO;
        _lastError = nil;
        _backoff = 0;
        _generation++;
        [self changed:YES];
    }
    return status;
}
- (NSDictionary *)settings { return [_contract settingsWithDefaults:[_store dictionaryForKey:@"settings"]]; }
- (void)changed:(BOOL)judge {
    [NSNotificationCenter.defaultCenter postNotificationName:NFChanged object:self userInfo:@{@"judge": @(judge)}];
}
- (void)saveSettings:(NSDictionary *)settings {
    [_store setObject:[_contract settingsOverrides:settings] forKey:@"settings"];
    _verdictNamespace = [_contract namespaceForGuidance:_instructions model:self.settings[@"model"]];
    [self changed:YES];
}
- (void)saveInstructions:(NSString *)instructions {
    NSString *text = [_contract guidance:instructions];
    if ([text isEqualToString:self.instructions]) return;
    [_store setObject:text forKey:@"instructions"];
    _instructions = [text copy];
    _verdictNamespace = [_contract namespaceForGuidance:_instructions model:self.settings[@"model"]];
    [self changed:YES];
    [self upgrade];
}
- (void)clearVerdicts {
    for (NSString *key in _store.dictionaryRepresentation) if ([key hasPrefix:@"v:"]) [_store removeObjectForKey:key];
    _generation++;
    [self changed:YES];
}
- (void)allow:(NSString *)videoID { if (NFVideoID(videoID)) [_store setBool:YES forKey:[@"a:" stringByAppendingString:videoID]]; [self changed:NO]; }
- (void)clearAllowed {
    for (NSString *key in _store.dictionaryRepresentation) if ([key hasPrefix:@"a:"]) [_store removeObjectForKey:key];
    [self changed:NO];
}
- (BOOL)allowed:(NSString *)videoID { return [_store boolForKey:[@"a:" stringByAppendingString:videoID]]; }
- (NSString *)cacheKey:(NSString *)videoID { return [NSString stringWithFormat:@"v:%@:%@", self.verdictNamespace, videoID]; }
- (NSDictionary *)verdictForVideo:(NSString *)videoID {
    NSData *data = [_store dataForKey:[self cacheKey:videoID]];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}
- (NSString *)reasonForVideo:(NSString *)videoID {
    return !self.enabled || [self allowed:videoID] ? nil : [_contract reason:[self verdictForVideo:videoID] settings:self.settings];
}
- (void)judge:(NSString *)videoID {
    if (self.enabled && NFVideoID(videoID) && ![self allowed:videoID] && ![self verdictForVideo:videoID]) [self enqueue:videoID transcript:nil];
}
- (void)enqueue:(NSString *)videoID transcript:(NSString *)transcript {
    NSString *identity = [NSString stringWithFormat:@"%lu:%@:%d", (unsigned long)_generation, [self cacheKey:videoID], transcript != nil];
    if (_jobs[identity] || !self.enabled || !self.hasKey || NSDate.timeIntervalSinceReferenceDate < _backoff) return;
    NFJob *job = [NFJob new];
    job.videoID = videoID;
    job.guidance = self.instructions;
    job.cacheKey = [self cacheKey:videoID];
    job.identity = identity;
    job.generation = _generation;
    job.transcript = transcript;
    job.settings = self.settings;
    _jobs[identity] = job;
    [_queue addObject:job];
    [self drain];
}
- (BOOL)current:(NFJob *)job { return job.generation == _generation && self.enabled && ![self allowed:job.videoID]; }
- (void)drain {
    while (_active < 4 && _queue.count) {
        NFJob *job = _queue.firstObject;
        [_queue removeObjectAtIndex:0];
        if (![self current:job] || NSDate.timeIntervalSinceReferenceDate < _backoff) {
            [_jobs removeObjectForKey:job.identity];
            continue;
        }
        _active++;
        [self fetchVideo:job];
    }
}
- (void)finish:(NFJob *)job verdict:(NSDictionary *)verdict {
    if (verdict && [self current:job]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:verdict options:0 error:nil];
        if (data) [_store setObject:data forKey:job.cacheKey];
    }
    [_jobs removeObjectForKey:job.identity];
    _active--;
    [self drain];
    [self changed:NO];
    if (verdict && !job.transcript && _openedVideo && [job.cacheKey isEqualToString:[self cacheKey:_openedVideo]]) [self upgrade];
}
- (BOOL)accept:(NSData *)data response:(NSHTTPURLResponse *)response job:(NFJob *)job {
    if (![self current:job]) return NO;
    if (response.statusCode == 429) {
        NSString *retryAfter = [response valueForHTTPHeaderField:@"Retry-After"];
        NSTimeInterval seconds = retryAfter.doubleValue;
        if (seconds <= 0 && retryAfter.length) {
            NSDateFormatter *format = [NSDateFormatter new];
            format.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            format.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            format.dateFormat = @"EEE',' dd MMM yyyy HH':'mm':'ss zzz";
            seconds = [format dateFromString:retryAfter].timeIntervalSinceNow;
        }
        if (seconds <= 0) seconds = [response.URL.host isEqualToString:@"api.typesafe.ai"] ? 60 : 600;
        _backoff = MAX(_backoff, NSDate.timeIntervalSinceReferenceDate + seconds);
    }
    if ([response.URL.host isEqualToString:@"api.typesafe.ai"]) {
        if (response.statusCode == 401 || response.statusCode == 403) _keyRejected = YES;
        if (response.statusCode == 200) _keyRejected = NO;
    }
    if (!data || response.statusCode != 200) {
        _lastError = response ? [NSString stringWithFormat:@"%@ returned HTTP %ld", response.URL.host, (long)response.statusCode]
                              : @"Network request failed";
    }
    return data != nil && response.statusCode == 200;
}
- (void)fetchVideo:(NFJob *)job {
    NSURL *url = [NSURL URLWithString:[@"https://www.youtube.com/watch?v=" stringByAppendingString:job.videoID]];
    [_http request:[NSURLRequest requestWithURL:url] limit:4000000 player:YES reply:^(NSData *data, NSHTTPURLResponse *response) {
        if (![self accept:data response:response job:job]) { [self finish:job verdict:nil]; return; }
        NSDictionary *player = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *details = [player isKindOfClass:NSDictionary.class] ? player[@"videoDetails"] : nil;
        if (![details isKindOfClass:NSDictionary.class] || ![details[@"videoId"] isEqual:job.videoID] || ![details[@"title"] isKindOfClass:NSString.class]) {
            self->_lastError = @"YouTube did not return this video's metadata";
            [self finish:job verdict:nil]; return;
        }
        id seconds = details[@"lengthSeconds"];
        double length = [seconds isKindOfClass:NSString.class] || [seconds isKindOfClass:NSNumber.class] ? [seconds doubleValue] : 0;
        NSDictionary *video = @{ @"title": details[@"title"], @"channel": details[@"author"] ?: @"", @"description": details[@"shortDescription"] ?: @"", @"seconds": @(length), @"live": @([details[@"isLiveContent"] isEqual:@YES]) };
        id captions = player[@"captions"];
        id renderer = [captions isKindOfClass:NSDictionary.class] ? captions[@"playerCaptionsTracklistRenderer"] : nil;
        id tracks = [renderer isKindOfClass:NSDictionary.class] ? renderer[@"captionTracks"] : nil;
        BOOL captioned = [tracks isKindOfClass:NSArray.class] && [tracks count] > 0;
        [self fetchThumbnail:job video:video captioned:captioned];
    }];
}
- (void)fetchThumbnail:(NFJob *)job video:(NSDictionary *)video captioned:(BOOL)captioned {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/hqdefault.jpg", job.videoID]];
    [_http request:[NSURLRequest requestWithURL:url] limit:200000 player:NO reply:^(NSData *data, NSHTTPURLResponse *response) {
        if (![self accept:data response:response job:job] || ![response.MIMEType isEqualToString:@"image/jpeg"]) { [self finish:job verdict:nil]; return; }
        NSDictionary *body = [self.contract call:@"decisionRequest" arguments:@[video, [data base64EncodedStringWithOptions:0], job.transcript ?: @"", job.guidance, job.settings]];
        NSString *key = self.key;
        if (!body || !key.length) { [self finish:job verdict:nil]; return; }
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.contract.endpoint]];
        request.HTTPMethod = @"POST";
        [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setValue:@"true" forHTTPHeaderField:@"TypeSafe-Danger-Zone-Images"];
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        job.requestID = NSUUID.UUID.UUIDString;
        [self increment:@"requests" by:1];
        [self->_http request:request limit:1000000 player:NO reply:^(NSData *answer, NSHTTPURLResponse *reply) {
            id parsed = answer ? [NSJSONSerialization JSONObjectWithData:answer options:NSJSONReadingFragmentsAllowed error:nil] : nil;
            if (reply.statusCode == 200) {
                [self increment:@"responses" by:1];
                id usage = [parsed isKindOfClass:NSDictionary.class] ? parsed[@"usage"] : nil;
                id tokens = [usage isKindOfClass:NSDictionary.class] ? usage[@"input_tokens"] : nil;
                if ([tokens isKindOfClass:NSNumber.class] && [tokens doubleValue] >= 0) [self increment:@"inputTokens" by:[tokens unsignedIntegerValue]];
                else [self increment:@"responsesWithoutUsage" by:1];
            }
            if (![self accept:answer response:reply job:job]) { [self finish:job verdict:nil]; return; }
            NSMutableDictionary *verdict = [[self.contract call:@"parseDecision" arguments:@[parsed ?: NSNull.null, body[@"questions"]]] mutableCopy];
            if (verdict) {
                BOOL unsure = [[self.contract call:@"needsTranscript" arguments:@[verdict, job.settings]] boolValue];
                verdict[@"transcript"] = job.transcript ? @"used" : unsure ? (captioned ? @"awaiting" : @"none") : @"not_needed";
                verdict[@"model"] = job.settings[@"model"];
                verdict[@"reportedModel"] = [parsed[@"model"] isKindOfClass:NSString.class] ? parsed[@"model"] : NSNull.null;
                verdict[@"requestID"] = job.requestID;
                verdict[@"judgedAt"] = @(NSDate.date.timeIntervalSince1970);
                self->_lastError = nil;
            } else self->_lastError = @"TypeSafe returned an invalid judgment";
            [self finish:job verdict:verdict];
        }];
    }];
}
- (void)increment:(NSString *)name by:(NSUInteger)value {
    NSString *key = [@"jev." stringByAppendingString:name];
    [_store setInteger:[_store integerForKey:key] + value forKey:key];
}
- (NSDictionary *)diagnostics {
    NSMutableDictionary *verdicts = [NSMutableDictionary new];
    NSString *prefix = [NSString stringWithFormat:@"v:%@:", _verdictNamespace];
    for (NSString *key in _store.dictionaryRepresentation) {
        if (![key hasPrefix:prefix]) continue;
        NSString *videoID = [key substringFromIndex:prefix.length];
        NSDictionary *verdict = [self verdictForVideo:videoID];
        if (verdict) verdicts[videoID] = verdict;
    }
    return @{@"endpoint": _contract.endpoint, @"model": self.settings[@"model"], @"namespace": _verdictNamespace,
             @"companionBuild": _contract.revision,
             @"enabled": @(self.enabled), @"hasKey": @(_hasKey), @"keychainStatus": @(_keychainStatus),
             @"keyRejected": @(_keyRejected), @"requests": @([_store integerForKey:@"jev.requests"]),
             @"responses": @([_store integerForKey:@"jev.responses"]), @"inputTokens": @([_store integerForKey:@"jev.inputTokens"]),
             @"responsesWithoutUsage": @([_store integerForKey:@"jev.responsesWithoutUsage"]),
             @"active": @(_active), @"queued": @(_queue.count), @"lastError": _lastError ?: NSNull.null,
             @"blockedUntil": _backoff > NSDate.timeIntervalSinceReferenceDate ? @([NSDate dateWithTimeIntervalSinceReferenceDate:_backoff].timeIntervalSince1970) : NSNull.null,
             @"verdicts": verdicts};
}
- (void)openedVideo:(NSString *)videoID owner:(id)owner {
    _openedVideo = [videoID copy];
    _captionOwner = owner;
    _captionText = nil;
}
- (void)captions:(NSString *)text video:(NSString *)videoID owner:(id)owner {
    if (!owner || owner != _captionOwner || ![videoID isEqualToString:_openedVideo] || !text.length) return;
    _captionText = [text substringToIndex:MIN(text.length, [_contract.limits[@"transcript"] unsignedIntegerValue])];
    [self upgrade];
}
- (void)upgrade {
    if (!_openedVideo || !_captionText.length || [self allowed:_openedVideo]) return;
    if ([[self verdictForVideo:_openedVideo][@"transcript"] isEqualToString:@"awaiting"]) [self enqueue:_openedVideo transcript:_captionText];
}
@end
