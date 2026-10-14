#import "NFService.h"

NSString *const NFChanged = @"NFChanged";
BOOL NFVideoID(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length != 11) return NO;
    NSCharacterSet *valid = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"];
    return [value rangeOfCharacterFromSet:valid.invertedSet].location == NSNotFound;
}

@interface NFJob : NSObject
@property(nonatomic, copy) NSString *videoID, *guidance, *cacheKey, *identity, *transcript;
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
}
+ (instancetype)shared {
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
    }
    return self;
}
- (void)dealloc { [_http invalidate]; }
- (NSDictionary *)keyQuery {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: _keyService, (__bridge id)kSecAttrAccount: @"openai-api-key"};
}
- (NSString *)key {
    NSMutableDictionary *query = [self.keyQuery mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef value = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &value) != errSecSuccess) return nil;
    return [[NSString alloc] initWithData:CFBridgingRelease(value) encoding:NSUTF8StringEncoding];
}
- (BOOL)hasKey { return self.key.length > 0; }
- (OSStatus)saveKey:(NSString *)key {
    key = [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    OSStatus status;
    if (!key.length) {
        status = SecItemDelete((__bridge CFDictionaryRef)self.keyQuery);
        if (status == errSecItemNotFound) status = errSecSuccess;
    } else {
        NSDictionary *value = @{(__bridge id)kSecValueData: [key dataUsingEncoding:NSUTF8StringEncoding],
                               (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly};
        status = SecItemUpdate((__bridge CFDictionaryRef)self.keyQuery, (__bridge CFDictionaryRef)value);
        if (status == errSecItemNotFound) {
            NSMutableDictionary *item = [self.keyQuery mutableCopy];
            [item addEntriesFromDictionary:value];
            status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
        }
    }
    if (status == errSecSuccess) { _generation++; [self changed:NO]; }
    return status;
}
- (NSDictionary *)settings { return [_store dictionaryForKey:@"settings"] ?: _contract.defaults; }
- (NSString *)instructions { return [_contract guidance:[_store stringForKey:@"instructions"]]; }
- (NSString *)namespace { return [_contract namespaceForGuidance:self.instructions]; }
- (void)changed:(BOOL)judge {
    [NSNotificationCenter.defaultCenter postNotificationName:NFChanged object:self userInfo:@{@"judge": @(judge)}];
}
- (void)saveSettings:(NSDictionary *)settings { [_store setObject:settings forKey:@"settings"]; [self changed:NO]; }
- (void)saveInstructions:(NSString *)instructions {
    NSString *text = [_contract guidance:instructions];
    if ([text isEqualToString:self.instructions]) return;
    [_store setObject:text forKey:@"instructions"];
    [self changed:YES];
    [self upgrade];
}
- (void)clearVerdicts {
    for (NSString *key in _store.dictionaryRepresentation) if ([key hasPrefix:@"v:"]) [_store removeObjectForKey:key];
    _generation++;
    [self changed:NO];
}
- (void)allow:(NSString *)videoID { if (NFVideoID(videoID)) [_store setBool:YES forKey:[@"a:" stringByAppendingString:videoID]]; [self changed:NO]; }
- (void)clearAllowed {
    for (NSString *key in _store.dictionaryRepresentation) if ([key hasPrefix:@"a:"]) [_store removeObjectForKey:key];
    [self changed:NO];
}
- (BOOL)allowed:(NSString *)videoID { return [_store boolForKey:[@"a:" stringByAppendingString:videoID]]; }
- (NSString *)cacheKey:(NSString *)videoID { return [NSString stringWithFormat:@"v:%@:%@", self.namespace, videoID]; }
- (NSDictionary *)verdictForVideo:(NSString *)videoID {
    NSData *data = [_store dataForKey:[self cacheKey:videoID]];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}
- (NSString *)reasonForVideo:(NSString *)videoID {
    return [self allowed:videoID] ? nil : [_contract reason:[self verdictForVideo:videoID] settings:self.settings];
}
- (void)judge:(NSString *)videoID {
    if (NFVideoID(videoID) && ![self allowed:videoID] && ![self verdictForVideo:videoID]) [self enqueue:videoID transcript:nil];
}
- (void)enqueue:(NSString *)videoID transcript:(NSString *)transcript {
    NSString *identity = [NSString stringWithFormat:@"%lu:%@:%d", (unsigned long)_generation, [self cacheKey:videoID], transcript != nil];
    if (_jobs[identity] || !self.hasKey || NSDate.timeIntervalSinceReferenceDate < _backoff) return;
    NFJob *job = [NFJob new];
    job.videoID = videoID;
    job.guidance = self.instructions;
    job.cacheKey = [self cacheKey:videoID];
    job.identity = identity;
    job.generation = _generation;
    job.transcript = transcript;
    _jobs[identity] = job;
    [_queue addObject:job];
    [self drain];
}
- (BOOL)current:(NFJob *)job { return job.generation == _generation && ![self allowed:job.videoID]; }
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
        [self changed:NO];
    }
    [_jobs removeObjectForKey:job.identity];
    _active--;
    [self drain];
    if (verdict && !job.transcript) [self upgrade];
}
- (BOOL)accept:(NSData *)data response:(NSHTTPURLResponse *)response job:(NFJob *)job {
    if (![self current:job]) return NO;
    if (response.statusCode == 429) {
        NSTimeInterval seconds = [[response valueForHTTPHeaderField:@"Retry-After"] doubleValue];
        if (seconds <= 0) seconds = [response.URL.host isEqualToString:@"api.openai.com"] ? 60 : 600;
        _backoff = MAX(_backoff, NSDate.timeIntervalSinceReferenceDate + seconds);
    }
    return data != nil && response.statusCode == 200;
}
- (void)fetchVideo:(NFJob *)job {
    NSURL *url = [NSURL URLWithString:[@"https://www.youtube.com/watch?v=" stringByAppendingString:job.videoID]];
    [_http request:[NSURLRequest requestWithURL:url] limit:4000000 player:YES reply:^(NSData *data, NSHTTPURLResponse *response) {
        if (![self accept:data response:response job:job]) { [self finish:job verdict:nil]; return; }
        NSDictionary *player = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *details = [player isKindOfClass:NSDictionary.class] ? player[@"videoDetails"] : nil;
        if (![details isKindOfClass:NSDictionary.class] || ![details[@"videoId"] isEqual:job.videoID] || ![details[@"title"] isKindOfClass:NSString.class]) { [self finish:job verdict:nil]; return; }
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
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/mqdefault.jpg", job.videoID]];
    [_http request:[NSURLRequest requestWithURL:url] limit:200000 player:NO reply:^(NSData *data, NSHTTPURLResponse *response) {
        if (![self accept:data response:response job:job] || ![response.MIMEType isEqualToString:@"image/jpeg"]) { [self finish:job verdict:nil]; return; }
        NSDictionary *body = [self.contract call:@"decisionRequest" arguments:@[video, [data base64EncodedStringWithOptions:0], job.transcript ?: @"", job.guidance]];
        NSString *key = self.key;
        if (!body || !key.length) { [self finish:job verdict:nil]; return; }
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.contract.endpoint]];
        request.HTTPMethod = @"POST";
        [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        [self->_http request:request limit:1000000 player:NO reply:^(NSData *answer, NSHTTPURLResponse *reply) {
            if (![self accept:answer response:reply job:job]) { [self finish:job verdict:nil]; return; }
            id parsed = [NSJSONSerialization JSONObjectWithData:answer options:NSJSONReadingFragmentsAllowed error:nil];
            NSMutableDictionary *verdict = [[self.contract call:@"parseDecision" arguments:@[parsed ?: NSNull.null, body[@"questions"]]] mutableCopy];
            if (verdict) {
                BOOL unsure = [[self.contract call:@"needsTranscript" arguments:@[verdict]] boolValue];
                verdict[@"transcript"] = job.transcript ? @"used" : unsure ? (captioned ? @"awaiting" : @"none") : @"not_needed";
            }
            [self finish:job verdict:verdict];
        }];
    }];
}
- (void)openedVideo:(NSString *)videoID owner:(id)owner {
    _openedVideo = [videoID copy];
    _captionOwner = owner;
    _captionText = nil;
}
- (void)captions:(NSString *)text video:(NSString *)videoID owner:(id)owner {
    if (owner != _captionOwner || ![videoID isEqualToString:_openedVideo] || !text.length) return;
    _captionText = [text substringToIndex:MIN(text.length, [_contract.limits[@"transcript"] unsignedIntegerValue])];
    [self upgrade];
}
- (void)upgrade {
    if (!_openedVideo || !_captionText.length || [self allowed:_openedVideo]) return;
    if ([[self verdictForVideo:_openedVideo][@"transcript"] isEqualToString:@"awaiting"]) [self enqueue:_openedVideo transcript:_captionText];
}
@end
