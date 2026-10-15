#import "NFService.h"

static void Check(BOOL ok, NSString *message) { if (!ok) { fprintf(stderr, "%s\n", message.UTF8String); exit(1); } }
static void Wait(BOOL (^ready)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:8];
    while (!ready() && end.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    Check(ready(), @"Timed out waiting for native fixture");
}
static NSData *JSON(id value) { return [NSJSONSerialization dataWithJSONObject:value options:0 error:nil]; }
static id Decode(id value) {
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *out = [NSMutableArray new];
        for (id item in value) [out addObject:Decode(item)];
        return out;
    }
    if ([value isKindOfClass:NSDictionary.class] && value[@"utf16"]) {
        NSMutableString *text = [NSMutableString new];
        for (NSNumber *unit in value[@"utf16"]) { unichar c = unit.unsignedShortValue; [text appendString:[NSString stringWithCharacters:&c length:1]]; }
        return text;
    }
    return value;
}

@interface Fixture : NSURLProtocol
@property(nonatomic) NSDictionary *body;
@property(nonatomic) NSString *videoID;
- (void)answer:(id)body status:(NSInteger)status;
@end
static NSMutableArray<Fixture *> *pending;
static NSMutableArray<NSDictionary *> *sent;
static BOOL wrongVideo;

@implementation Fixture
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        Check(![self.request valueForHTTPHeaderField:@"Cookie"], @"Cookie leaked into native request");
        NSString *host = self.request.URL.host;
        if ([host isEqual:@"www.youtube.com"]) {
            self.videoID = self.request.URL.query;
            self.videoID = [self.videoID substringFromIndex:2];
            NSDictionary *player = @{@"videoDetails": @{@"videoId": wrongVideo ? @"WRONGVIDEO1" : self.videoID, @"title": self.videoID, @"author": @"Fixture", @"shortDescription": @"Text } { with \\\" quotes", @"lengthSeconds": @"61"}, @"captions": @{@"playerCaptionsTracklistRenderer": @{@"captionTracks": @[@{}]}}};
            NSMutableData *html = [[@"<script>var ytInitialPlayerResponse = \n" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
            [html appendData:JSON(player)];
            [html appendData:[@"; throw new Error('must not run');</script>" dataUsingEncoding:NSUTF8StringEncoding]];
            [self send:html status:200 type:@"text/html"];
        } else if ([host isEqual:@"i.ytimg.com"]) {
            [self send:[NSData dataWithBytes:"\xff\xd8\xff\xd9" length:4] status:200 type:@"image/jpeg"];
        } else {
            Check([host isEqual:@"api.openai.com"], @"Unexpected request host");
            NSData *body = self.request.HTTPBody;
            if (!body) {
                NSInputStream *stream = self.request.HTTPBodyStream;
                [stream open];
                NSMutableData *bytes = [NSMutableData new];
                uint8_t buffer[4096]; NSInteger n;
                while ((n = [stream read:buffer maxLength:sizeof(buffer)]) > 0) [bytes appendBytes:buffer length:(NSUInteger)n];
                [stream close]; body = bytes;
            }
            self.body = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
            Check(self.body != nil, @"No Decisions request body");
            [sent addObject:self.body];
            [pending addObject:self];
        }
    });
}
- (void)send:(NSData *)bytes status:(NSInteger)status type:(NSString *)type {
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": type, @"Retry-After": @"60"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    for (NSUInteger i = 0; i < bytes.length; i += 17) [self.client URLProtocol:self didLoadData:[bytes subdataWithRange:NSMakeRange(i, MIN(17, bytes.length - i))]];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)answer:(id)body status:(NSInteger)status {
    [pending removeObject:self];
    [self send:JSON(body) status:status type:@"application/json"];
}
- (void)stopLoading {}
@end

static NSDictionary *Answer(Fixture *request, double score, double uncertainty) {
    NSMutableArray *answers = [NSMutableArray new];
    for (NSDictionary *question in request.body[@"questions"]) {
        [answers addObject:@{@"name": question[@"name"], @"type": @"choice", @"probabilities": @[
            @{@"value": question[@"choices"][0][@"value"], @"probability": @(score)},
            @{@"value": @"uncertain", @"probability": @(uncertainty)},
            @{@"value": @"no_signal", @"probability": @(1 - score - uncertainty)}]}];
    }
    return @{@"answers": answers};
}
static void Respond(double score, double uncertainty) { Fixture *r = pending.firstObject; [r answer:Answer(r, score, uncertainty) status:200]; }
static void AwaitNew(NFService *service, NSString *videoID) {
    NSUInteger count = sent.count;
    [service judge:videoID];
    Wait(^BOOL { return sent.count > count; });
}

@interface NFService (CompletionObservation)
- (void)finish:(id)job verdict:(NSDictionary *)verdict;
- (void)fetchVideo:(id)job;
@end
@interface ObservedService : NFService
@property(nonatomic) NSUInteger started, running, peak, completions;
@end
@implementation ObservedService
- (void)fetchVideo:(id)job {
    self.started++; self.running++; self.peak = MAX(self.peak, self.running);
    [super fetchVideo:job];
}
- (void)finish:(id)job verdict:(NSDictionary *)verdict {
    Check(self.running > 0, @"A native job finished twice");
    self.running--;
    [super finish:job verdict:verdict]; self.completions++;
}
@end
static void Idle(ObservedService *service) { Wait(^BOOL { return service.running == 0; }); }

int main(int argc, char **argv) { @autoreleasepool {
    Check(argc == 2, @"Expected parity fixture path");
    NSDictionary *fixtures = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:nil];
    NFContract *contract = [NFContract new];
    Check(contract && fixtures, @"JavaScriptCore or fixture failed to initialize");
    for (NSDictionary *item in fixtures[@"cases"]) {
        id result = [contract call:item[@"name"] arguments:Decode(item[@"args"])];
        Check([(result ?: NSNull.null) isEqual:item[@"expected"]], [@"Native contract parity: " stringByAppendingString:item[@"name"]]);
    }
    Check([contract.categories isEqual:fixtures[@"categories"]] && [contract.defaults isEqual:fixtures[@"defaults"]], @"Labels/settings differ from original module");
    Check([[contract namespaceForGuidance:[contract guidance:Decode(fixtures[@"guidance"])]] isEqual:fixtures[@"hash"]], @"Unicode guidance hash differs from request text");
    NSDictionary *verdict = @{@"scores": @{@"noise": @0.8}, @"reasons": @{@"noise": @"clickbait"}};
    for (NSString *strictness in contract.strictnessNames) {
        NSDictionary *settings = @{@"categories": @{@"noise": @YES}, @"strictness": strictness};
        Check(([contract reason:verdict settings:settings] != nil) == ![strictness isEqual:@"lenient"], @"Native threshold selection differs");
    }
    Check(![contract reason:verdict settings:@{@"categories": @{@"noise": @YES}, @"strictness": @"unknown"}], @"Unknown strictness must fail visible");
    Check(![contract reason:verdict settings:@{@"categories": @{@"noise": @YES}}], @"Missing strictness must fail visible");
    NSString *domain = [@"noise-filter-fixture." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *store = [[NSUserDefaults alloc] initWithSuiteName:domain];
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.protocolClasses = @[Fixture.class];
    ObservedService *service = [[ObservedService alloc] initWithDefaults:store configuration:configuration keyService:domain];
    pending = [NSMutableArray new]; sent = [NSMutableArray new];
    Check([service saveKey:@"fixture-key-one"] == errSecSuccess && service.hasKey, @"Native Keychain save/read failed");
    Check(![store.dictionaryRepresentation.description containsString:@"fixture-key"], @"Key persisted outside Keychain");
    Check(configuration.HTTPCookieStorage == nil && configuration.URLCache == nil && !configuration.HTTPShouldSetCookies, @"Transport shares cookies or cache");
    NSString *a = @"AAAAAAAAAA1";
    AwaitNew(service, a); NSUInteger before = service.started; [service judge:a];
    Check(service.started == before, @"Duplicate video request did not join");
    Respond(0.8, 0); Idle(service);
    before = service.started;
    [service saveSettings:@{@"categories": @{}, @"strictness": @"strict"}];
    Check(![service reasonForVideo:a] && service.started == before, @"Switches re-requested or did not re-render");
    [service saveInstructions:@"  Hide anime.\n"];
    AwaitNew(service, a); Respond(1, 0); Idle(service);
    Check([[service reasonForVideo:a] isEqual:@"Matches your instructions"], @"Topic instructions require quality switches");
    before = service.started;
    [service saveInstructions:@""]; [service judge:a];
    Check([service verdictForVideo:a][@"scores"] != nil && service.started == before, @"Original namespace was not reused");
    [service saveInstructions:@"Hide anime."]; [service judge:a];
    Check([[service reasonForVideo:a] isEqual:@"Matches your instructions"] && service.started == before, @"Guidance namespace was not reused");
    [service allow:a]; Check(![service reasonForVideo:a], @"Show anyway did not restore a hiding verdict");
    [service saveInstructions:@"Different instructions"]; [service judge:a];
    Check(service.started == before, @"Persistent allow depends on instructions");
    [service saveInstructions:@"Hide anime."];
    Check([service verdictForVideo:a] && ![service reasonForVideo:a], @"Allow lost on return to a hiding namespace");
    service = [[ObservedService alloc] initWithDefaults:store configuration:configuration keyService:domain];
    [service judge:a];
    Check(service.started == 0 && [service verdictForVideo:a] && ![service reasonForVideo:a], @"Verdict/allow lost across service restart");
    NSString *b = @"BBBBBBBBBB1";
    AwaitNew(service, b); Fixture *old = pending.firstObject;
    [service saveInstructions:@"Another namespace"]; AwaitNew(service, b);
    [old answer:Answer(old, 0.8, 0) status:200]; Respond(0, 0);
    Idle(service);
    Check(![service reasonForVideo:b], @"Old guidance result applied to current namespace");
    [service saveInstructions:@"Hide anime."];
    Check([service reasonForVideo:b] != nil, @"Old namespace result was not saved under its own guidance");
    NSString *c = @"CCCCCCCCCC1";
    AwaitNew(service, c); old = pending.firstObject;
    Check([service saveKey:@"fixture-key-two"] == errSecSuccess, @"Key replacement failed");
    AwaitNew(service, c);
    Fixture *fresh = pending.lastObject;
    [fresh answer:Answer(fresh, 0, 0) status:200];
    Wait(^BOOL { return [service verdictForVideo:c] != nil; });
    [old answer:Answer(old, 1, 0) status:200]; Idle(service);
    Check([[service verdictForVideo:c][@"scores"][@"custom_instructions"] doubleValue] == 0, @"Old key completion overwrote replacement generation");
    NSString *d = @"DDDDDDDDDD1";
    AwaitNew(service, d); [service clearVerdicts]; Respond(1, 0); Idle(service);
    Check(![service verdictForVideo:d], @"Clear accepted stale metadata");
    AwaitNew(service, d); Respond(0.6, 0.3); Idle(service);
    Check([[service verdictForVideo:d][@"transcript"] isEqual:@"awaiting"], @"Uncertain verdict does not await captions");
    NSObject *view = [NSObject new], *later = [NSObject new];
    [service openedVideo:d owner:view]; [service openedVideo:d owner:later];
    before = service.started;
    [service captions:@"Stale view" video:d owner:view];
    [service captions:@"Wrong video" video:c owner:later];
    Check(service.started == before, @"Mismatched caption owner or ID accepted");
    [service captions:@"Current view" video:d owner:later];
    before = service.started;
    [service captions:@"Duplicate capture" video:d owner:later];
    Check(service.started == before, @"Duplicate caption capture started another job");
    Wait(^BOOL { return pending.count == 1; });
    NSUInteger finished = service.completions;
    [pending.firstObject answer:@{} status:500];
    Wait(^BOOL { return service.completions > finished; });
    Check([[service verdictForVideo:d][@"transcript"] isEqual:@"awaiting"], @"Failed upgrade removed the metadata verdict");
    NSString *unrelated = @"KKKKKKKKKK1";
    AwaitNew(service, unrelated); before = service.started;
    Respond(0, 0);
    Wait(^BOOL { return [service verdictForVideo:unrelated] != nil; });
    Check(service.started == before, @"Unrelated metadata completion retried failed captions");
    [service captions:@"Later caption request" video:d owner:later];
    Wait(^BOOL { return pending.count == 1; }); Respond(0, 0);
    Idle(service);
    Check([[service verdictForVideo:d][@"transcript"] isEqual:@"used"], @"Caption upgrade was not saved");
    before = service.started;
    [service captions:@"More captions" video:d owner:later]; Check(service.started == before, @"Completed captions were bought twice");
    NSString *early = @"IIIIIIIIII1";
    [service openedVideo:early owner:view];
    AwaitNew(service, early);
    [service captions:@"Captions before the verdict" video:early owner:view];
    Respond(0.6, 0.3);
    Wait(^BOOL { return pending.count == 1; });
    Check([pending.firstObject.body[@"input"][0][@"content"] count] == 4, @"Early captions were not retained for the view");
    [service clearVerdicts];
    finished = service.completions;
    Respond(1, 0);
    Wait(^BOOL { return service.completions > finished; });
    Check(![service verdictForVideo:early], @"Clear accepted a stale caption upgrade");
    before = service.started; [service judge:a]; Check(service.started == before, @"Clear verdicts removed persistent allow");
    [service openedVideo:nil owner:nil];
    NSString *e = @"EEEEEEEEEE1";
    for (id invalid in @[@{}, @{@"answers": @[]}, @{@"answers": @[@{@"name": @"noise", @"type": @"refusal"}]}]) {
        AwaitNew(service, e); [pending.firstObject answer:invalid status:200]; Idle(service);
        Check(![service verdictForVideo:e], @"Invalid/refused response was cached");
    }
    AwaitNew(service, e); [pending.firstObject answer:@{} status:500]; Idle(service);
    AwaitNew(service, e); [pending.firstObject answer:@{} status:401]; Idle(service);
    AwaitNew(service, e);
    Fixture *network = pending.firstObject; [pending removeObject:network];
    [network.client URLProtocol:network didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost userInfo:nil]];
    Idle(service);
    AwaitNew(service, e); Respond(0, 0); Idle(service);
    wrongVideo = YES;
    before = service.started;
    [service judge:@"FFFFFFFFFF1"]; Idle(service);
    [service judge:@"FFFFFFFFFF1"]; Idle(service);
    Check(service.started == before + 2, @"Failed watch-page request could not be retried");
    Check(![service verdictForVideo:@"FFFFFFFFFF1"], @"Mismatched watch video was cached");
    wrongVideo = NO;
    [service clearVerdicts]; Idle(service); service.peak = 0;
    NSArray *ids = @[@"GGGGGGGGGG1", @"GGGGGGGGGG2", @"GGGGGGGGGG3", @"GGGGGGGGGG4", @"GGGGGGGGGG5", @"GGGGGGGGGG6"];
    NSUInteger paid = sent.count;
    for (NSString *videoID in ids) [service judge:videoID];
    Wait(^BOOL { return pending.count == 4; });
    while (sent.count < paid + ids.count || pending.count) {
        if (pending.count) Respond(0, 0);
        else Wait(^BOOL { return pending.count > 0; });
    }
    Idle(service);
    Check(service.peak == 4, @"Actual native job concurrency must reach four without exceeding it");
    AwaitNew(service, @"HHHHHHHHHH1");
    finished = service.completions;
    [pending.firstObject answer:@{} status:429];
    Wait(^BOOL { return service.completions > finished; });
    before = service.started;
    [service judge:@"HHHHHHHHHH2"];
    Check(service.started == before, @"429 did not stop new jobs");
    NFHTTP *bounded = [[NFHTTP alloc] initWithConfiguration:configuration];
    __block BOOL boundedDone = NO;
    [bounded request:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.youtube.com/watch?v=JJJJJJJJJJ1"]] limit:64 player:NO reply:^(NSData *data, NSHTTPURLResponse *response) {
        Check(!data && response.statusCode == 200, @"Response byte bound was not enforced"); boundedDone = YES;
    }];
    Wait(^BOOL { return boundedDone; }); [bounded invalidate];
    Check([service saveKey:@""] == errSecSuccess && !service.hasKey, @"Key deletion failed");
    [store removePersistentDomainForName:domain];
    puts("Native contract, Keychain, NSURLSession, persistence, generations, captions and concurrency checks passed");
    return 0;
} }
