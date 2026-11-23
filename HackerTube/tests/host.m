// Simulator host for the companion's sources. YouTube cannot run in a simulator, so the classes
// below stand in for the YouTube classes the companion looks up by name and record what the real
// ones would be asked to do. The first launch runs with the switch off and turns it on; the second
// launch finds the Home replacement installed by the companion's own constructor.
//
// Built with HKT_SITE_URL, Home loads this file's fixture server; built without it, Home loads
// the live site and only the checks that hold there run.

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import "HackerTube.h"
#import "HKTRoute.h"
#import "HKTWebViewController.h"

static NSString *const HomeID = @"FEwhat_to_watch";
static const NSUInteger Section = 0x686B7462;
static BOOL SmokeOnly;
static BOOL SwitchOnAtLaunch;
static NSUInteger Failures;

#pragma mark Stand-ins for YouTube classes

@interface YTBaseInnerTubeViewController : UIViewController
@property (nonatomic) NSUInteger requests;
@end
@implementation YTBaseInnerTubeViewController
- (void)makeRequestForRefresh:(BOOL)refresh disablePrepareToRefresh:(BOOL)disablePrepare nonContinuationRefresh:(BOOL)nonContinuation {
    self.requests++;
}
@end

@interface YTBrowseViewController : YTBaseInnerTubeViewController
@property (nonatomic, copy) NSString *browseIdentifier;
@property (nonatomic) NSUInteger appearances;
@end
@implementation YTBrowseViewController
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.appearances++;
}
@end

@interface YTHeaderContentComboView : UIView
@property (nonatomic, strong) UIView *headerView;
@end
@implementation YTHeaderContentComboView
@end

@interface YTICommand : NSObject
@property (nonatomic, copy) NSString *videoID;
@end
@implementation YTICommand
+ (instancetype)watchNavigationEndpointWithVideoID:(NSString *)videoID {
    YTICommand *command = [self new];
    command.videoID = videoID;
    return command;
}
@end

@interface YTAccountScopedCommandResponderEvent : NSObject
@property (nonatomic, strong) YTICommand *command;
@property (nonatomic, strong) UIView *fromView;
@property (nonatomic, strong) id entry;
@property (nonatomic) BOOL sendClick;
@property (nonatomic, strong) id firstResponder;
@end
static NSMutableArray<YTAccountScopedCommandResponderEvent *> *SentEvents;
@implementation YTAccountScopedCommandResponderEvent
+ (instancetype)eventForActiveIdentityInGlobalScopeWithCommand:(YTICommand *)command fromView:(UIView *)view entry:(id)entry sendClick:(BOOL)sendClick firstResponder:(id)firstResponder {
    YTAccountScopedCommandResponderEvent *event = [self new];
    event.command = command;
    event.fromView = view;
    event.entry = entry;
    event.sendClick = sendClick;
    event.firstResponder = firstResponder;
    return event;
}
- (void)send {
    [SentEvents addObject:self];
}
@end

@interface YTSettingsGroupData : NSObject
@property (nonatomic, readonly) NSUInteger type;
@property (nonatomic, readonly) NSArray<NSNumber *> *orderedCategories;
@end
@implementation YTSettingsGroupData
- (instancetype)initWithType:(NSUInteger)type categories:(NSArray<NSNumber *> *)categories {
    if ((self = [super init])) {
        _type = type;
        _orderedCategories = categories;
    }
    return self;
}
@end

@protocol YTAppSettingsSectionItemDataDelegate
- (void)setSectionItems:(NSMutableArray *)items forCategory:(NSUInteger)category title:(NSString *)title icon:(id)icon titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden;
@end

@interface SettingsRecorder : NSObject <YTAppSettingsSectionItemDataDelegate>
@property (nonatomic, strong) NSArray *items;
@property (nonatomic) NSUInteger category;
@property (nonatomic, copy) NSString *title;
@end
@implementation SettingsRecorder
- (void)setSectionItems:(NSMutableArray *)items forCategory:(NSUInteger)category title:(NSString *)title icon:(id)icon titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden {
    self.items = items;
    self.category = category;
    self.title = title;
}
@end

@interface YTSettingsSectionItemManager : NSObject {
    __weak id<YTAppSettingsSectionItemDataDelegate> _dataDelegate;
}
@property (nonatomic, strong) NSMutableArray<NSNumber *> *nativeUpdates;
@end
@implementation YTSettingsSectionItemManager
- (instancetype)initWithDataDelegate:(id<YTAppSettingsSectionItemDataDelegate>)delegate {
    if ((self = [super init])) {
        _dataDelegate = delegate;
        _nativeUpdates = [NSMutableArray new];
    }
    return self;
}
- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    [self.nativeUpdates addObject:@(category)];
}
@end

@interface YTSettingsSectionItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *titleDescription;
@property (nonatomic) BOOL switchOn;
@property (nonatomic, copy) BOOL (^switchBlock)(id cell, BOOL on);
@end
@implementation YTSettingsSectionItem
+ (instancetype)switchItemWithTitle:(NSString *)title titleDescription:(NSString *)titleDescription accessibilityIdentifier:(NSString *)identifier switchOn:(BOOL)on switchBlock:(BOOL (^)(id cell, BOOL on))block settingItemId:(int)itemID {
    YTSettingsSectionItem *item = [self new];
    item.title = title;
    item.titleDescription = titleDescription;
    item.switchOn = on;
    item.switchBlock = block;
    return item;
}
@end

@interface PlaybackOwner : NSObject
@property (nonatomic, strong) PlaybackOwner *parentResponder;
@property (nonatomic, strong) PlaybackOwner *playerViewControllerTraits;
@property (nonatomic, copy) NSString *name;
@end
@implementation PlaybackOwner
@end

@interface YTLocalPlaybackController : PlaybackOwner
@property (nonatomic) BOOL nativeAllowsBackground;
@property (nonatomic, getter=isActivePlayback) BOOL activePlayback;
@property (nonatomic) BOOL lockScreenVisible;
- (BOOL)isPlaybackBackgroundable;
- (void)appDidEnterBackground;
- (void)updateLockScreenController;
@end
@implementation YTLocalPlaybackController
- (BOOL)isPlaybackBackgroundable { return self.nativeAllowsBackground; }
- (void)appDidEnterBackground {}
- (void)updateLockScreenController { self.lockScreenVisible = self.isPlaybackBackgroundable; }
@end

@interface YTPlayerPIPController : NSObject
@property (nonatomic, weak) PlaybackOwner *delegate;
@property (nonatomic) BOOL nativeAllowsPiP;
- (BOOL)canEnablePictureInPicture;
@end
@implementation YTPlayerPIPController
- (BOOL)canEnablePictureInPicture { return self.nativeAllowsPiP; }
@end

// Lays its content out under a top bar, as the app does with a frosted top bar.
@interface ComboController : UIViewController
@end
@implementation ComboController {
    UIViewController *_content;
    CGFloat _barHeight;
}
- (instancetype)initWithContent:(UIViewController *)content barHeight:(CGFloat)barHeight {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _content = content;
        _barHeight = barHeight;
    }
    return self;
}
- (void)loadView {
    YTHeaderContentComboView *view = [YTHeaderContentComboView new];
    [self addChildViewController:_content];
    [view addSubview:_content.view];
    view.headerView = [UIView new];
    view.headerView.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.6];
    [view addSubview:view.headerView];
    self.view = view;
    [_content didMoveToParentViewController:self];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _content.view.frame = self.view.bounds;
    ((YTHeaderContentComboView *)self.view).headerView.frame = CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), _barHeight);
}
@end

#pragma mark Helpers

static void Check(BOOL ok, NSString *what) {
    if (!ok) Failures++;
    printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    fflush(stdout);
}

static BOOL Wait(NSTimeInterval seconds, BOOL (^done)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done()) {
        if (end.timeIntervalSinceNow < 0) return NO;
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    return YES;
}

static void Settle(NSTimeInterval seconds) {
    Wait(seconds, ^BOOL { return NO; });
}

static id Script(WKWebView *view, NSString *source) {
    __block id result;
    __block BOOL finished = NO;
    [view evaluateJavaScript:source completionHandler:^(id value, NSError *error) {
        result = value;
        finished = YES;
    }];
    Wait(10, ^BOOL { return finished; });
    return result;
}

static UIView *Find(UIView *root, BOOL (^matches)(UIView *view)) {
    if (matches(root)) return root;
    for (UIView *subview in root.subviews) {
        UIView *found = Find(subview, matches);
        if (found) return found;
    }
    return nil;
}

static WKWebView *WebView(UIViewController *controller) {
    return (WKWebView *)Find(controller.view, ^BOOL(UIView *view) { return [view isKindOfClass:WKWebView.class]; });
}

static UIView *Identified(UIViewController *controller, NSString *identifier) {
    return Find(controller.view, ^BOOL(UIView *view) { return [view.accessibilityIdentifier isEqual:identifier]; });
}

static YTBrowseViewController *Browse(NSString *identifier) {
    YTBrowseViewController *controller = [YTBrowseViewController new];
    controller.browseIdentifier = identifier;
    return controller;
}

static void Request(YTBrowseViewController *controller) {
    [controller makeRequestForRefresh:NO disablePrepareToRefresh:NO nonContinuationRefresh:NO];
}

static uint16_t FreePort(void) {
    int probe = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address = {.sin_len = sizeof(address), .sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    socklen_t length = sizeof(address);
    bind(probe, (struct sockaddr *)&address, length);
    getsockname(probe, (struct sockaddr *)&address, &length);
    close(probe);
    return ntohs(address.sin_port);
}

// Answers every GET on 127.0.0.1:port with `page`, as the site answers every path with its one
// page. With `unavailableFirst` the first request gets status 503 and an error page instead.
static BOOL Serve(uint16_t port, NSData *page, BOOL unavailableFirst) {
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    int yes = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in address = {.sin_len = sizeof(address), .sin_family = AF_INET, .sin_port = htons(port), .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(listener, 16) != 0) return NO;
    __block BOOL unavailable = unavailableFirst;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        for (;;) {
            int client = accept(listener, NULL, NULL);
            if (client < 0) continue;
            int on = 1;
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
            char request[8192];
            read(client, request, sizeof(request));
            NSData *body = unavailable ? [@"<h1>503 Service Unavailable</h1>" dataUsingEncoding:NSUTF8StringEncoding] : page;
            NSString *head = [NSString stringWithFormat:@"HTTP/1.1 %s\r\nContent-Type: text/html; charset=utf-8\r\n"
                               "Content-Length: %lu\r\nConnection: close\r\n\r\n",
                               unavailable ? "503 Service Unavailable" : "200 OK", (unsigned long)body.length];
            unavailable = NO;
            write(client, head.UTF8String, strlen(head.UTF8String));
            write(client, body.bytes, body.length);
            close(client);
        }
    });
    return YES;
}

#pragma mark Checks

static void CheckSettings(void) {
    NSNumber *section = @(Section);
    YTSettingsGroupData *account = [[YTSettingsGroupData alloc] initWithType:1 categories:@[@1, @5]];
    YTSettingsGroupData *playback = [[YTSettingsGroupData alloc] initWithType:2 categories:@[@7]];
    Check([account.orderedCategories isEqual:@[section, @1, @5]] && [playback.orderedCategories isEqual:@[@7]],
          @"without YouGroupSettings the section joins settings group 1 only");

    SettingsRecorder *recorder = [SettingsRecorder new];
    YTSettingsSectionItemManager *manager = [[YTSettingsSectionItemManager alloc] initWithDataDelegate:recorder];
    [manager updateSectionForCategory:3 withEntry:nil];
    [manager updateSectionForCategory:Section withEntry:nil];
    YTSettingsSectionItem *toggle = recorder.items.firstObject;
    Check([manager.nativeUpdates isEqual:@[@3]] && recorder.items.count == 2 && recorder.category == Section
          && [recorder.title isEqual:@"HackerTube"] && [toggle.title isEqual:@"HackerTube Home"]
          && toggle.switchOn == SwitchOnAtLaunch && [toggle.titleDescription containsString:@"Restart YouTube"],
          @"the Home switch shows the saved mode and says a restart applies it");

    YTSettingsSectionItem *shorts = recorder.items.lastObject;
    YTPlayerPIPController *pip = [YTPlayerPIPController new];
    YTLocalPlaybackController *local = [YTLocalPlaybackController new];
    local.nativeAllowsBackground = YES;
    local.parentResponder = [PlaybackOwner new];
    PlaybackOwner *traits = [PlaybackOwner new];
    local.parentResponder.playerViewControllerTraits = traits;
    pip.delegate = local;
    pip.nativeAllowsPiP = YES;
    traits.name = @"com.google.youtube.reel.watch";
    Check(!shorts.switchOn && !pip.canEnablePictureInPicture, @"Shorts PiP is off by default");
    Check(!local.isPlaybackBackgroundable, @"a Short cannot keep background audio or lock screen controls");
    Check(shorts.switchBlock(nil, YES) && pip.canEnablePictureInPicture && local.isPlaybackBackgroundable,
          @"the same Shorts switch restores the native PiP and background playback decisions");
    pip.nativeAllowsPiP = NO;
    local.nativeAllowsBackground = NO;
    Check(!pip.canEnablePictureInPicture && !local.isPlaybackBackgroundable,
          @"allowing background playback for Shorts does not override native denials");
    shorts.switchBlock(nil, NO);
    local.nativeAllowsBackground = YES;
    local.lockScreenVisible = YES;
    [local appDidEnterBackground];
    Check(local.lockScreenVisible, @"a cached Short does not clear the lock screen on backgrounding");
    local.activePlayback = YES;
    [local appDidEnterBackground];
    Check(!local.lockScreenVisible, @"leaving a paused active Short clears previously published controls");
    traits.name = @"com.google.youtube.youtube.watch";
    Check(!pip.canEnablePictureInPicture, @"a regular player's native denial is preserved");
    Check(local.isPlaybackBackgroundable, @"regular background audio is independent of a native PiP denial");
    pip.nativeAllowsPiP = YES;
    local.nativeAllowsBackground = NO;
    Check(pip.canEnablePictureInPicture && !local.isPlaybackBackgroundable,
          @"a regular player can have PiP without background audio after a Short");

    static NSMutableArray<NSNumber *> *tweaks;
    tweaks = [@[@200] mutableCopy];
    class_addMethod(object_getClass(YTSettingsGroupData.class), NSSelectorFromString(@"tweaks"),
                    imp_implementationWithBlock(^(id cls) { return tweaks; }), "@@:");
    YTSettingsGroupData *tweakGroup = [[YTSettingsGroupData alloc] initWithType:0x70737974 categories:tweaks];
    Check([tweakGroup.orderedCategories isEqual:@[@200, section]] && [account.orderedCategories isEqual:@[@1, @5]],
          @"with YouGroupSettings the section joins its Tweaks group instead");

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    Check(toggle.switchBlock(nil, !SwitchOnAtLaunch) && [defaults boolForKey:HKTHomeEnabledKey] == !SwitchOnAtLaunch,
          @"the switch saves the mode for the next launch");
}

// A class that has one method as the shape declares it, one with another return type, and lacks the third.
@protocol MemberShape
- (void)present;
- (NSInteger)retyped;
- (void)absent;
@end

@interface MemberProbe : NSObject
@end
@implementation MemberProbe
- (void)present {
}
- (void)retyped {
}
@end

static void NeverInstalled(id self, SEL _cmd) {
}

static void CheckMembers(void) {
    Protocol *shape = @protocol(MemberShape);
    IMP before = class_getMethodImplementation(MemberProbe.class, @selector(retyped)), original = NULL;
    HKTReplace(MemberProbe.class, shape, @selector(retyped), YES, (IMP)NeverInstalled, &original);
    HKTReplace(MemberProbe.class, shape, @selector(absent), YES, (IMP)NeverInstalled, &original);
    Check(HKTMethod(MemberProbe.class, shape, @selector(present), YES) != NULL
          && HKTMethod(MemberProbe.class, shape, @selector(retyped), YES) == NULL
          && HKTMethod(MemberProbe.class, shape, @selector(absent), YES) == NULL
          && original == NULL && class_getMethodImplementation(MemberProbe.class, @selector(retyped)) == before
          && ![MemberProbe instancesRespondToSelector:@selector(absent)],
          @"a member that is missing or has another type encoding is neither found nor replaced");
}

static void CheckRoutes(void) {
    NSURL *home = [NSURL URLWithString:@"https://hackertube.org/"];
    NSDictionary<NSString *, NSNumber *> *expected = @{
        @"https://hackertube.org/browse?dur=xlong": @(HKTRouteInSite),
        @"https://hackertube.org/watchlist": @(HKTRouteInSite),
        @"https://hackertube.org/watch/dQw4w9WgXcQ": @(HKTRouteVideo),
        @"https://m.youtube.com/watch?t=5&v=dQw4w9WgXcQ": @(HKTRouteVideo),
        @"https://hackertube.org/watch/dQw4w9WgXcQ/extra": @(HKTRouteBlocked),
        @"https://www.youtube.com/watch?v=short": @(HKTRouteBlocked),
        @"youtube://watch?v=dQw4w9WgXcQ": @(HKTRouteBlocked),
        @"http://hackertube.org/": @(HKTRouteExternal),
        @"https://hackertube.org:8443/": @(HKTRouteExternal),
        @"https://hackertube.org.evil.com/watch/dQw4w9WgXcQ": @(HKTRouteExternal),
        @"https://hackertube.org@evil.com/watch/dQw4w9WgXcQ": @(HKTRouteExternal),
        @"https://youtu.be/dQw4w9WgXcQ": @(HKTRouteExternal),
    };
    NSMutableArray<NSString *> *wrong = [NSMutableArray new];
    for (NSString *link in expected) {
        if (HKTRouteForURL([NSURL URLWithString:link], home, NULL) != expected[link].integerValue) [wrong addObject:link];
    }
    Check(wrong.count == 0, [@"links are routed by exact origin, path and video id" stringByAppendingString:
        wrong.count ? [@"; wrong for " stringByAppendingString:[wrong componentsJoinedByString:@" "]] : @""]);
}

static void RunSwitchOff(UIWindow *window) {
    YTBrowseViewController *home = Browse(HomeID);
    window.rootViewController = [[ComboController alloc] initWithContent:home barHeight:120];
    Wait(5, ^BOOL { return home.appearances == 1; });
    Request(home);
    SEL request = @selector(makeRequestForRefresh:disablePrepareToRefresh:nonContinuationRefresh:);
    Check(home.appearances == 1 && home.requests == 1 && home.childViewControllers.count == 0 && home.view.subviews.count == 0
          && class_getMethodImplementation(YTBrowseViewController.class, request)
             == class_getMethodImplementation(YTBaseInnerTubeViewController.class, request),
          @"with the switch off Home requests its own feed, gets no web view and has no request override");
    CheckMembers();
    CheckRoutes();
    CheckSettings();
}

static void RunSwitchOn(UIWindow *window) {
    SentEvents = [NSMutableArray new];
    NSMutableArray<NSURL *> *externals = [NSMutableArray new];
    YTBrowseViewController *home = Browse(HomeID);
    window.rootViewController = [[ComboController alloc] initWithContent:home barHeight:120];
    Wait(5, ^BOOL { return home.childViewControllers.count == 1; });
    HKTWebViewController *web = (HKTWebViewController *)home.childViewControllers.firstObject;
    Check([web isKindOfClass:HKTWebViewController.class] && home.view.subviews.lastObject == web.view
          && CGRectEqualToRect(web.view.frame, home.view.bounds),
          @"Home shows the web view as its front-most, full-size child");

    Request(home);
    Check(home.requests == 0 && home.childViewControllers.count == 1, @"Home makes no native feed request");

    if (!SmokeOnly) {
        YTBrowseViewController *subscriptions = Browse(@"FEsubscriptions");
        [subscriptions beginAppearanceTransition:YES animated:NO];
        [subscriptions endAppearanceTransition];
        Request(subscriptions);
        Check(subscriptions.appearances == 1 && subscriptions.requests == 1 && subscriptions.childViewControllers.count == 0,
              @"another browse page requests its feed and gets no web view");
    }

    [window layoutIfNeeded];
    WKWebView *view = WebView(web);
    Check(fabs(CGRectGetMinY(view.frame) - 120) < 0.5 && web.view.safeAreaInsets.bottom > 0
          && fabs(CGRectGetMaxY(view.frame) - (CGRectGetHeight(web.view.bounds) - web.view.safeAreaInsets.bottom)) < 0.5,
          @"the web view starts below the top bar and ends at the bottom safe area");
    // Links that leave the app are recorded here instead of opening Safari in the simulator.
    Method openURL = class_getInstanceMethod(UIApplication.class, @selector(openURL:options:completionHandler:));
    method_setImplementation(openURL, imp_implementationWithBlock(^(id app, NSURL *url, id options, id completion) {
        [externals addObject:url];
    }));
    YTAccountScopedCommandResponderEvent * (^event)(NSUInteger) = ^(NSUInteger index) {
        return index < SentEvents.count ? SentEvents[index] : nil;
    };

#ifdef HKT_SITE_URL
    NSString *route = @"location.pathname + '|' + window.routed.join()";
    Check(Wait(20, ^BOOL { return [Script(view, @"document.readyState === 'complete' && Array.isArray(window.routed)") boolValue]; }),
          @"Home loads the site's page");

    Script(view, @"document.getElementById('card').click()");
    Wait(5, ^BOOL { return SentEvents.count > 0; });
    Settle(0.5);
    Check(SentEvents.count == 1 && [event(0).command.videoID isEqual:@"dQw4w9WgXcQ"] && event(0).firstResponder == home
          && event(0).fromView == home.view && !event(0).sendClick && !event(0).entry,
          @"a card tap sends exactly one watch event for its video from the Home controller");
    Check([Script(view, route) isEqual:@"/|"], @"a card tap leaves the page where it was instead of on the watch page");
    if (SmokeOnly) return;

    Script(view, @"document.getElementById('later').click()");
    Settle(0.5);
    Check(SentEvents.count == 1 && [Script(view, @"window.later") isEqual:@1],
          @"a control inside a card that handles its own tap does not open the video");

    Script(view, @"document.getElementById('bad').click()");
    Settle(0.5);
    Check(SentEvents.count == 1 && [Script(view, route) isEqual:@"/|"], @"a watch link with a malformed video id goes nowhere");

    Script(view, @"document.getElementById('external').click()");
    Wait(5, ^BOOL { return externals.count > 0; });
    Settle(0.5);
    Check(externals.count == 1 && [externals.firstObject.absoluteString isEqual:@"https://news.ycombinator.com/item?id=1"]
          && [view.URL.host isEqual:@"127.0.0.1"], @"a tapped link to another site is handed to the system once");

    Script(view, @"location.href = 'https://example.com/'");
    Settle(1);
    Check(externals.count == 1 && [view.URL.host isEqual:@"127.0.0.1"], @"a script cannot take the web view to another site or open one");

    Script(view, @"location.href = '/watch/dQw4w9WgXcQ'");
    Settle(1);
    Check(SentEvents.count == 1 && [Script(view, route) isEqual:@"/|"], @"a script navigation to a watch link plays nothing and goes nowhere");

    Script(view, @"document.getElementById('youtube').click()");
    Wait(5, ^BOOL { return SentEvents.count > 1; });
    Settle(0.5);
    Check(SentEvents.count == 2 && [event(1).command.videoID isEqual:@"9bZkp7q19f0"], @"a YouTube watch link plays in the app");

    Script(view, @"document.getElementById('browse').click()");
    Settle(0.5);
    Check([Script(view, route) isEqual:@"/browse|/browse"] && SentEvents.count == 2 && externals.count == 1,
          @"a same-site link stays in the web view under the site's own routing");
    Check(Identified(web, @"hackertube.failure").hidden && !view.hidden, @"none of the cancelled links shows the failure message");
#else
    NSString *card = @"document.querySelector(\"a.vcard[href^='/watch/']\")";
    Check(Wait(40, ^BOOL { return [Script(view, [card stringByAppendingString:@" !== null"]) boolValue]; }),
          @"live: hackertube.org loads its feed inside Home");
    NSString *videoID = Script(view, [card stringByAppendingString:@".getAttribute('href').split('/').pop()"]);
    puts("HKT-SCREENSHOT");
    fflush(stdout);
    Settle(6);

    Script(view, @"document.querySelector(\"a.vcard [data-later]\").click()");
    Settle(1);
    Check(SentEvents.count == 0 && [Script(view, @"location.pathname") isEqual:@"/"],
          @"live: the Watch later button inside a card does not open the video");

    Script(view, [card stringByAppendingString:@".click()"]);
    Wait(5, ^BOOL { return SentEvents.count > 0; });
    Settle(1);
    Check(SentEvents.count == 1 && videoID.length == 11 && [event(0).command.videoID isEqual:videoID] && event(0).firstResponder == home,
          @"live: a card tap sends exactly one watch event for that card's video");
    Check([Script(view, @"location.pathname") isEqual:@"/"] && [Script(view, @"document.querySelector('iframe') === null") boolValue],
          @"live: the page stays on the feed and renders no embedded player");

    Script(view, @"document.querySelector(\"a[href='/browse']\").click()");
    Check(Wait(10, ^BOOL { return [Script(view, @"location.pathname") isEqual:@"/browse"]; }) && SentEvents.count == 1 && externals.count == 0,
          @"live: a same-site link stays in the web view");
    Check(Identified(web, @"hackertube.failure").hidden && !view.hidden, @"live: no failure message");
    printf("live: first card video id %s\n", videoID.UTF8String);
#endif

    uint16_t port = FreePort();
    NSURL *unreachable = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%d/", port]];
    HKTWebViewController *offline = [[HKTWebViewController alloc] initWithHomeURL:unreachable
        openVideo:^(NSString *videoID) {} openExternal:^(NSURL *url) {}];
    window.rootViewController = offline;
    UIView *failure = Identified(offline, @"hackertube.failure");
    Check(failure.hidden, @"no failure message while the first load is in progress");
    Check(Wait(20, ^BOOL { return !failure.hidden; }) && WebView(offline).hidden,
          @"an unreachable site shows the failure message instead of the page");
    NSData *page = [NSData dataWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"fixture" withExtension:@"html"]];
    Check(Serve(port, page, YES), @"the site becomes reachable");
    UIButton *retry = (UIButton *)Identified(offline, @"hackertube.retry");
    [retry sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    BOOL (^namesStatus)(UIView *) = ^BOOL(UIView *label) {
        return [label isKindOfClass:UILabel.class] && [((UILabel *)label).text containsString:@"503"];
    };
    Wait(20, ^BOOL { return !failure.hidden; });
    // WebKit reports the cancelled load once more as an error of its own; the status stays the reason.
    Settle(0.5);
    Check(!failure.hidden && Find(failure, namesStatus) && WebView(offline).hidden,
          @"an HTTP error status shows the failure message with that status instead of the server's error page");
    [retry sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    Check(Wait(20, ^BOOL { return failure.hidden && [Script(WebView(offline), @"Array.isArray(window.routed)") boolValue]; })
          && !WebView(offline).hidden, @"Retry loads the page and removes the failure message");
    CheckSettings();
}

#pragma mark App

@interface HKTTestApp : UIResponder <UIApplicationDelegate>
@end
@implementation HKTTestApp
@end

@interface HKTTestScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation HKTTestScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) {
        if (SmokeOnly) Check(SwitchOnAtLaunch, @"the smoke launch enables HackerTube Home");
        if (SwitchOnAtLaunch) RunSwitchOn(self.window);
        else if (!SmokeOnly) RunSwitchOff(self.window);
        [NSUserDefaults.standardUserDefaults synchronize];
        const char *result = Failures ? "FAIL" : "PASS";
        if (SmokeOnly) printf("HackerTube smoke: %s\n", result);
        else printf("HackerTube checks with the switch %s: %s\n", SwitchOnAtLaunch ? "on" : "off", result);
        fflush(stdout);
        exit(Failures ? 1 : 0);
    }];
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        SmokeOnly = [NSProcessInfo.processInfo.arguments containsObject:@"--smoke"];
        SwitchOnAtLaunch = [NSUserDefaults.standardUserDefaults boolForKey:HKTHomeEnabledKey];
#ifdef HKT_SITE_URL
        NSURL *site = [NSURL URLWithString:@HKT_SITE_URL];
        NSData *page = [NSData dataWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"fixture" withExtension:@"html"]];
        if (!page || !Serve(site.port.unsignedShortValue, page, NO)) {
            puts("FAIL fixture server could not start");
            return 1;
        }
#endif
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(HKTTestApp.class));
    }
}
