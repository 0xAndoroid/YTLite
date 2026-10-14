#import "NFHTTP.h"

@interface NFRead : NSObject
@property(nonatomic) NSMutableData *bytes;
@property(nonatomic) NSHTTPURLResponse *response;
@property(nonatomic, copy) NFHTTPReply reply;
@property(nonatomic) NSUInteger limit, scanned, start;
@property(nonatomic) NSInteger depth;
@property(nonatomic) BOOL player, quoted, escaped;
@end
@implementation NFRead
@end

@implementation NFHTTP {
    NSURLSession *_session;
    NSMutableDictionary<NSNumber *, NFRead *> *_reads;
}
- (instancetype)initWithConfiguration:(NSURLSessionConfiguration *)configuration {
    if ((self = [super init])) {
        configuration.HTTPCookieStorage = nil;
        configuration.HTTPShouldSetCookies = NO;
        configuration.URLCache = nil;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        configuration.timeoutIntervalForRequest = 30;
        configuration.timeoutIntervalForResource = 60;
        _reads = [NSMutableDictionary new];
        _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:NSOperationQueue.mainQueue];
    }
    return self;
}
- (void)invalidate { [_session invalidateAndCancel]; }
- (void)request:(NSURLRequest *)request limit:(NSUInteger)limit player:(BOOL)player reply:(NFHTTPReply)reply {
    NFRead *read = [NFRead new];
    read.bytes = [NSMutableData new];
    read.limit = limit;
    read.player = player;
    read.start = NSNotFound;
    read.reply = reply;
    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request];
    _reads[@(task.taskIdentifier)] = read;
    [task resume];
}
- (void)finish:(NSURLSessionTask *)task data:(NSData *)data {
    NFRead *read = _reads[@(task.taskIdentifier)];
    [_reads removeObjectForKey:@(task.taskIdentifier)];
    [task cancel];
    if (read) read.reply(data, read.response);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completion {
    completion(nil);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    NFRead *read = _reads[@(task.taskIdentifier)];
    read.response = (NSHTTPURLResponse *)response;
    BOOL accepted = read.response.statusCode == 200 && (read.player || response.expectedContentLength <= (long long)read.limit);
    completion(accepted ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
    if (!accepted) [self finish:task data:nil];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    NFRead *read = _reads[@(task.taskIdentifier)];
    if (!read) return;
    if (data.length > read.limit - read.bytes.length) { [self finish:task data:nil]; return; }
    [read.bytes appendData:data];
    if (!read.player) return;
    if (read.start == NSNotFound) {
        NSData *marker = [@"var ytInitialPlayerResponse = " dataUsingEncoding:NSUTF8StringEncoding];
        NSRange found = [read.bytes rangeOfData:marker options:0 range:NSMakeRange(read.scanned, read.bytes.length - read.scanned)];
        if (found.location == NSNotFound) {
            read.scanned = read.bytes.length > marker.length ? read.bytes.length - marker.length : 0;
            return;
        }
        read.start = NSMaxRange(found);
        read.scanned = read.start;
    }
    const unsigned char *bytes = read.bytes.bytes;
    for (; read.scanned < read.bytes.length; read.scanned++) {
        unsigned char c = bytes[read.scanned];
        if (read.quoted) {
            if (read.escaped) read.escaped = NO;
            else if (c == '\\') read.escaped = YES;
            else if (c == '"') read.quoted = NO;
        } else if (c == '"') read.quoted = YES;
        else if (c == '{') read.depth++;
        else if (c == '}') read.depth--;
        else if (read.depth == 0 && (c == ' ' || c == '\n' || c == '\r' || c == '\t')) continue;
        if (!read.quoted && read.depth <= 0) {
            [self finish:task data:[read.bytes subdataWithRange:NSMakeRange(read.start, read.scanned + 1 - read.start)]];
            return;
        }
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NFRead *read = _reads[@(task.taskIdentifier)];
    [self finish:task data:error || read.player ? nil : read.bytes];
}
@end
