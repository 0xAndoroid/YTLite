#import "NFHome.h"
#import "NFRuntime.h"
#import "NFService.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>

static IMP OriginalDisplay, OriginalAppearance;
static __weak NFService *Service;
static NSMutableArray *Samples;
static NSUInteger HomeDisplays;
static NSTimeInterval CaptureUntil;
static BOOL Scheduled;

static id Object(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (![object respondsToSelector:selector]) return nil;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}
static BOOL Home(id controller) {
    id delegate = Object(controller, @"delegate");
    return [delegate isKindOfClass:NSClassFromString(@"YTSectionListViewController")] &&
        ((BOOL (*)(id, SEL))objc_msgSend)(delegate, @selector(isHomeFeed));
}
static NSString *VideoURL(NSString *value) {
    NSURLComponents *url = [NSURLComponents componentsWithString:value];
    NSString *videoID;
    if ([url.host isEqual:@"youtu.be"]) videoID = url.path.lastPathComponent;
    if (([url.host isEqual:@"www.youtube.com"] || [url.host isEqual:@"youtube.com"]) && [url.path isEqual:@"/watch"]) {
        for (NSURLQueryItem *item in url.queryItems) if ([item.name isEqual:@"v"]) videoID = item.value;
    }
    return NFVideoID(videoID) ? [@"https://www.youtube.com/watch?v=" stringByAppendingString:videoID] : nil;
}
static NSString *RedactedProto(NSString *text) {
    NSUInteger limit = MIN(text.length, (NSUInteger)32768), i = 0;
    NSMutableString *result = [NSMutableString new];
    while (i < limit) {
        unichar character = [text characterAtIndex:i++];
        if (character != '"') { [result appendFormat:@"%C", character]; continue; }
        NSUInteger start = i;
        BOOL closed = NO;
        while (i < limit) {
            character = [text characterAtIndex:i++];
            if (character == '\\') { i = MIN(i + 1, limit); continue; }
            if (character == '"') { closed = YES; break; }
        }
        NSString *value = [text substringWithRange:NSMakeRange(start, i - start - (closed ? 1 : 0))];
        NSString *field = [[result componentsSeparatedByString:@"\n"].lastObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        BOOL videoField = [@[@"video_id:", @"videoId:", @"videoID:"] containsObject:field];
        NSString *safe = closed ? VideoURL(value) : nil;
        if (closed && videoField && NFVideoID(value)) safe = value;
        [result appendFormat:@"\"%@\"", safe ?: @"<redacted>"];
    }
    if (text.length > limit) [result appendString:@"\n<truncated>"];
    return result;
}
static NSDictionary *Describe(id object, NSUInteger depth, NSHashTable *visited, NSUInteger *remaining) {
    if (!object || !*remaining) return @{};
    (*remaining)--;
    NSMutableDictionary *result = [@{@"class": NSStringFromClass([object class])} mutableCopy];
    if ([object isKindOfClass:NSString.class]) { result[@"characters"] = @([object length]); return result; }
    if ([object isKindOfClass:NSData.class]) { result[@"bytes"] = @([object length]); return result; }
    if (!depth || [visited containsObject:object]) return result;
    [visited addObject:object];
    if ([object isKindOfClass:NSClassFromString(@"ELMElement")]) {
        id text = Object(object, @"protoText");
        if ([text isKindOfClass:NSString.class]) result[@"redactedProto"] = RedactedProto(text);
    }
    for (NSString *name in @[@"videoId", @"videoID", @"entry", @"elementEntry", @"elementRenderer", @"element", @"nodeModel", @"navigationEndpoint", @"watchEndpoint"]) {
        id value = Object(object, name);
        if (!value) continue;
        if (([name isEqual:@"videoId"] || [name isEqual:@"videoID"]) && NFVideoID(value)) result[name] = value;
        else result[name] = Describe(value, depth - 1, visited, remaining);
    }
    return result;
}
NSDictionary *NFHomeDiagnostics(void) {
    return @{@"phase": @"identity-checkpoint", @"filteringImplemented": @NO,
             @"hooksInstalled": @((BOOL)(OriginalDisplay && OriginalAppearance)),
             @"homeDisplayCallbacks": @(HomeDisplays), @"captureUntil": @(CaptureUntil),
             @"observations": Samples ? [Samples copy] : @[]};
}
static BOOL WriteDiagnostics(NSError **error) {
    NSMutableDictionary *snapshot = [Service.diagnostics mutableCopy];
    if (!snapshot) return NO;
    snapshot[@"home"] = NFHomeDiagnostics();
    snapshot[@"capturedAt"] = @(NSDate.date.timeIntervalSince1970);
    snapshot[@"appVersion"] = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    NSString *file = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"NoiseFilter-diagnostics.json"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
    return data && [data writeToFile:file options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:error];
}
BOOL NFCaptureHome(NFService *service, NSError **error) {
    if (!NSThread.isMainThread || !service) return NO;
    Service = service;
    Samples = [NSMutableArray new];
    CaptureUntil = NSDate.date.timeIntervalSince1970 + 60;
    return WriteDiagnostics(error);
}
static void Capture(id controller) {
    if (!NSThread.isMainThread || Scheduled || !Samples || Samples.count >= 8 || NSDate.date.timeIntervalSince1970 >= CaptureUntil) return;
    if (!Home(controller)) return;
    Scheduled = YES;
    __weak id weakController = controller;
    dispatch_async(dispatch_get_main_queue(), ^{
        Scheduled = NO;
        id owner = weakController;
        if (!owner || !Home(owner) || NSDate.date.timeIntervalSince1970 >= CaptureUntil) return;
        UICollectionView *collection = Object(owner, @"collectionView");
        if (![collection isKindOfClass:UICollectionView.class]) return;
        NSArray *indices = [collection.indexPathsForVisibleItems sortedArrayUsingSelector:@selector(compare:)];
        for (NSIndexPath *index in indices) {
            if (Samples.count >= 8 || NSDate.date.timeIntervalSince1970 >= CaptureUntil) break;
            UICollectionViewCell *cell = [collection cellForItemAtIndexPath:index];
            if (!cell) continue;
            NSIndexPath *modelIndex = ((id (*)(id, SEL, id))objc_msgSend)(owner, @selector(modelIndexPathForPresentationIndexPath:), index);
            if (![modelIndex isKindOfClass:NSIndexPath.class] || !((BOOL (*)(id, SEL, id))objc_msgSend)(owner, @selector(isValidIndexPath:), modelIndex)) continue;
            id section = ((id (*)(id, SEL, id))objc_msgSend)(owner, @selector(sectionControllerAtIndexPath:), modelIndex);
            if (!section) continue;
            id item;
            if (NFMethodMatches([section class], @selector(cellControllerAtIndex:), "@24@0:8q16")) {
                item = ((id (*)(id, SEL, NSInteger))objc_msgSend)(section, @selector(cellControllerAtIndex:), [modelIndex item]);
            }
            NSUInteger remaining = 24;
            NSHashTable *visited = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
            CGRect frame = cell.frame;
            [Samples addObject:@{@"at": @(NSDate.date.timeIntervalSince1970),
                @"section": @(index.section), @"item": @(index.item), @"modelIndex": @[@([modelIndex section]), @([modelIndex item])],
                @"frame": @[@(frame.origin.x), @(frame.origin.y), @(frame.size.width), @(frame.size.height)],
                @"layoutClass": NSStringFromClass(collection.collectionViewLayout.class),
                @"cellClass": NSStringFromClass(cell.class), @"sectionClass": NSStringFromClass([section class]),
                @"cellController": Describe(item, 4, visited, &remaining),
                @"node": Describe(Object(cell, @"node"), 4, visited, &remaining)}];
        }
        WriteDiagnostics(NULL);
    });
}
static void Display(id self, SEL selector, UICollectionView *collection, UICollectionViewCell *cell, NSIndexPath *index) {
    ((void (*)(id, SEL, id, id, id))OriginalDisplay)(self, selector, collection, cell, index);
    if (!NSThread.isMainThread || !Home(self)) return;
    HomeDisplays++;
    Capture(self);
}
static void Appeared(id self, SEL selector, BOOL animated) {
    ((void (*)(id, SEL, BOOL))OriginalAppearance)(self, selector, animated);
    Capture(self);
}
BOOL NFInstallHomeHooks(NFService *service) {
    if (OriginalDisplay) return YES;
    Class cls = NSClassFromString(@"YTInnerTubeCollectionViewController");
    if (!NSThread.isMainThread || !service ||
        !NFMethodMatches(cls, @selector(collectionView:willDisplayCell:forItemAtIndexPath:), "v40@0:8@16@24@32") ||
        !NFMethodMatches(cls, @selector(viewDidAppear:), "v20@0:8B16") ||
        !NFMethodMatches(cls, @selector(delegate), "@16@0:8") ||
        !NFMethodMatches(cls, @selector(collectionView), "@16@0:8") ||
        !NFMethodMatches(cls, @selector(modelIndexPathForPresentationIndexPath:), "@24@0:8@16") ||
        !NFMethodMatches(cls, @selector(isValidIndexPath:), "B24@0:8@16") ||
        !NFMethodMatches(cls, @selector(sectionControllerAtIndexPath:), "@24@0:8@16") ||
        !NFMethodMatches(NSClassFromString(@"YTSectionListViewController"), @selector(isHomeFeed), "B16@0:8")) return NO;
    Service = service;
    OriginalDisplay = NFHook(cls, @selector(collectionView:willDisplayCell:forItemAtIndexPath:), "v40@0:8@16@24@32", (IMP)Display);
    OriginalAppearance = NFHook(cls, @selector(viewDidAppear:), "v20@0:8B16", (IMP)Appeared);
    return YES;
}
