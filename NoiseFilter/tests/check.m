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
static NSMutableSet<NSString *> *active;
static NSUInteger peak, watches;
static BOOL wrongVideo;

@implementation Fixture
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        Check(![self.request valueForHTTPHeaderField:@"Cookie"], @"Cookie leaked into native request");
        NSString *host = self.request.URL.host;
        if ([host isEqual:@"www.youtube.com"]) {
            watches++;
            self.videoID = self.request.URL.query;
            self.videoID = [self.videoID substringFromIndex:2];
            [active addObject:self.videoID];
            peak = MAX(peak, active.count);
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
    NSString *description = self.body[@"input"][0][@"content"][0][@"text"];
    for (NSString *videoID in active.copy) if ([description containsString:videoID]) [active removeObject:videoID];
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
    Wait(^BOOL { [service judge:videoID]; return sent.count > count; });
}

@interface NFService (CompletionObservation)
- (void)finish:(id)job verdict:(NSDictionary *)verdict;
@end
@interface ObservedService : NFService
@property(nonatomic) NSUInteger completions;
@end
@implementation ObservedService
- (void)finish:(id)job verdict:(NSDictionary *)verdict { [super finish:job verdict:verdict]; self.completions++; }
@end

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
    NSString *domain = [@"noise-filter-fixture." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *store = [[NSUserDefaults alloc] initWithSuiteName:domain];
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.protocolClasses = @[Fixture.class];
    ObservedService *service = [[ObservedService alloc] initWithDefaults:store configuration:configuration keyService:domain];
    pending = [NSMutableArray new]; sent = [NSMutableArray new]; active = [NSMutableSet new];
    Check([service saveKey:@"fixture-key-one"] == errSecSuccess && service.hasKey, @"Native Keychain save/read failed");
    Check(![store.dictionaryRepresentation.description containsString:@"fixture-key"], @"Key persisted outside Keychain");
    Check(configuration.HTTPCookieStorage == nil && configuration.URLCache == nil && !configuration.HTTPShouldSetCookies, @"Transport shares cookies or cache");
    NSString *a = @"AAAAAAAAAA1";
    AwaitNew(service, a); [service judge:a];
    Check(pending.count == 1, @"Duplicate video request did not join");
    Respond(0.8, 0); Wait(^BOOL { return [service verdictForVideo:a] != nil; });
    NSUInteger paid = sent.count;
    [service saveSettings:@{@"categories": @{}, @"strictness": @"strict"}];
    Check(![service reasonForVideo:a] && sent.count == paid, @"Switches re-requested or did not re-render");
    [service saveInstructions:@"  Hide anime.\n"];
    AwaitNew(service, a); Respond(1, 0); Wait(^BOOL { return [service verdictForVideo:a] != nil; });
    Check([[service reasonForVideo:a] isEqual:@"Matches your instructions"], @"Topic instructions require quality switches");
    paid = sent.count;
    [service saveInstructions:@""]; [service judge:a];
    Check([service verdictForVideo:a][@"scores"] != nil && sent.count == paid, @"Original namespace was not reused");
    [service saveInstructions:@"Hide anime."]; [service judge:a];
    Check([[service reasonForVideo:a] isEqual:@"Matches your instructions"] && sent.count == paid, @"Guidance namespace was not reused");
    [service allow:a]; [service saveInstructions:@"Different instructions"]; [service judge:a];
    Check(![service reasonForVideo:a] && sent.count == paid, @"Persistent allow depends on instructions");
    NFService *restarted = [[NFService alloc] initWithDefaults:store configuration:configuration keyService:domain];
    [restarted judge:a]; Check(sent.count == paid && ![restarted reasonForVideo:a], @"Allow lost across service restart");
    [restarted saveInstructions:@"Hide anime."];
    Check([restarted verdictForVideo:a] != nil, @"Verdict lost across service restart");
    restarted = nil;
    NSString *b = @"BBBBBBBBBB1";
    AwaitNew(service, b); Fixture *old = pending.firstObject;
    [service saveInstructions:@"Another namespace"]; AwaitNew(service, b);
    [old answer:Answer(old, 0.8, 0) status:200]; Respond(0, 0);
    Wait(^BOOL { return [service verdictForVideo:b] != nil; });
    Check(![service reasonForVideo:b], @"Old guidance result applied to current namespace");
    [service saveInstructions:@"Hide anime."];
    Wait(^BOOL { return [service verdictForVideo:b] != nil; });
    Check([service reasonForVideo:b] != nil, @"Old namespace result was not saved under its own guidance");
    NSString *c = @"CCCCCCCCCC1";
    AwaitNew(service, c); old = pending.firstObject;
    Check([service saveKey:@"fixture-key-two"] == errSecSuccess, @"Key replacement failed");
    AwaitNew(service, c); [old answer:Answer(old, 1, 0) status:200]; Respond(0, 0);
    Wait(^BOOL { return [service verdictForVideo:c] != nil; });
    Check(![service reasonForVideo:c], @"Old key completion overwrote replacement generation");
    NSString *d = @"DDDDDDDDDD1";
    AwaitNew(service, d); [service clearVerdicts]; Respond(1, 0);
    AwaitNew(service, d); Respond(0.6, 0.3); Wait(^BOOL { return [service verdictForVideo:d] != nil; });
    Check([[service verdictForVideo:d][@"transcript"] isEqual:@"awaiting"], @"Uncertain verdict does not await captions");
    NSObject *view = [NSObject new], *later = [NSObject new];
    [service openedVideo:d owner:view]; [service openedVideo:d owner:later];
    paid = sent.count;
    [service captions:@"Stale view" video:d owner:view]; Check(sent.count == paid, @"Old view captions accepted");
    [service captions:@"Current view" video:d owner:later];
    Wait(^BOOL { return pending.count == 1; });
    NSUInteger finished = service.completions;
    [pending.firstObject answer:@{} status:500];
    Wait(^BOOL { return service.completions > finished; });
    Check([[service verdictForVideo:d][@"transcript"] isEqual:@"awaiting"], @"Failed upgrade removed the metadata verdict");
    [service captions:@"Later caption request" video:d owner:later];
    Wait(^BOOL { return pending.count == 1; }); Respond(0, 0);
    Wait(^BOOL { return [[service verdictForVideo:d][@"transcript"] isEqual:@"used"]; });
    paid = sent.count;
    [service captions:@"More captions" video:d owner:later]; Check(sent.count == paid, @"Completed captions were bought twice");
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
    paid = sent.count; [service judge:a]; Check(sent.count == paid, @"Clear verdicts removed persistent allow");
    [service openedVideo:nil owner:nil];
    NSString *e = @"EEEEEEEEEE1";
    for (id invalid in @[@{}, @{@"answers": @[]}, @{@"answers": @[@{@"name": @"noise", @"type": @"refusal"}]}]) {
        AwaitNew(service, e); [pending.firstObject answer:invalid status:200];
    }
    AwaitNew(service, e); [pending.firstObject answer:@{} status:500];
    AwaitNew(service, e); [pending.firstObject answer:@{} status:401];
    AwaitNew(service, e);
    Fixture *network = pending.firstObject; [pending removeObject:network];
    [network.client URLProtocol:network didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost userInfo:nil]];
    AwaitNew(service, e); Respond(0, 0); Wait(^BOOL { return [service verdictForVideo:e] != nil; });
    wrongVideo = YES;
    NSUInteger before = watches;
    Wait(^BOOL { [service judge:@"FFFFFFFFFF1"]; return watches >= before + 2; });
    Check(![service verdictForVideo:@"FFFFFFFFFF1"], @"Mismatched watch video was cached");
    wrongVideo = NO;
    [service clearVerdicts]; [active removeAllObjects]; peak = 0;
    NSArray *ids = @[@"GGGGGGGGGG1", @"GGGGGGGGGG2", @"GGGGGGGGGG3", @"GGGGGGGGGG4", @"GGGGGGGGGG5", @"GGGGGGGGGG6"];
    paid = sent.count;
    for (NSString *videoID in ids) [service judge:videoID];
    Wait(^BOOL { return pending.count == 4; });
    while (sent.count < paid + ids.count || pending.count) {
        if (pending.count) Respond(0, 0);
        else Wait(^BOOL { return pending.count > 0; });
    }
    Wait(^BOOL { return [service verdictForVideo:ids.lastObject] != nil; });
    Check(peak == 4, @"Native video concurrency exceeded four");
    AwaitNew(service, @"HHHHHHHHHH1");
    finished = service.completions;
    [pending.firstObject answer:@{} status:429];
    Wait(^BOOL { return service.completions > finished; });
    before = watches;
    [service judge:@"HHHHHHHHHH2"];
    Check(watches == before, @"429 did not stop new jobs");
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
