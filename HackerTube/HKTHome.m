#import "HackerTube.h"
#import "HKTWebViewController.h"

#ifndef HKT_SITE_URL
#define HKT_SITE_URL "https://hackertube.org/"
#endif

// Shapes of the YouTube members used here, read from the 21.44.4 executable. HKTHomeSupported
// compares each with the running app's method before anything is hooked or called.
@protocol HKTBrowseViewController
- (NSString *)browseIdentifier;
- (void)viewWillAppear:(BOOL)animated;
- (void)makeRequestForRefresh:(BOOL)refresh disablePrepareToRefresh:(BOOL)disablePrepare nonContinuationRefresh:(BOOL)nonContinuation;
@end

@protocol HKTHeaderContentComboView
- (UIView *)headerView;
@end

@protocol HKTCommand
+ (id)watchNavigationEndpointWithVideoID:(NSString *)videoID;
@end

@protocol HKTCommandEvent
+ (id<HKTCommandEvent>)eventForActiveIdentityInGlobalScopeWithCommand:(id)command fromView:(UIView *)view entry:(id)entry sendClick:(BOOL)sendClick firstResponder:(id)firstResponder;
- (void)send;
@end

static NSString *const HomeBrowseID = @"FEwhat_to_watch";
static IMP OriginalRequest, OriginalAppear;
static BOOL HeaderKnown;
static const void *WebKey = &WebKey;

static BOOL IsHome(id controller) {
    NSString *identifier = [(id<HKTBrowseViewController>)controller browseIdentifier];
    return [identifier isKindOfClass:NSString.class] && [identifier isEqualToString:HomeBrowseID];
}

// How the app's own controls open a video: -[YTPlaylistHeaderViewController didTapPlayAll:] sends
// this event from its view with itself as first responder, and the app's navigation handler plays
// a watch endpoint.
static void OpenVideo(UIViewController *host, NSString *videoID) {
    if (!host) return;
    Class<HKTCommand> commands = NSClassFromString(@"YTICommand");
    Class<HKTCommandEvent> events = NSClassFromString(@"YTAccountScopedCommandResponderEvent");
    id command = [commands watchNavigationEndpointWithVideoID:videoID];
    [[events eventForActiveIdentityInGlobalScopeWithCommand:command fromView:host.view entry:nil sendClick:NO firstResponder:host] send];
}

// With a frosted top bar the app lays the browse view out under the bar
// (-[YTHeaderContentComboView layoutChildView]) and insets only its own collection view.
static CGFloat CoveredTop(UIViewController *host, UIView *view) {
    UIView *combo = host.viewIfLoaded.superview;
    if (!HeaderKnown || ![combo isKindOfClass:NSClassFromString(@"YTHeaderContentComboView")]) return 0;
    UIView *header = [(id<HKTHeaderContentComboView>)combo headerView];
    if (![header isKindOfClass:UIView.class] || header.hidden) return 0;
    CGRect covered = CGRectIntersection([header convertRect:header.bounds toView:view], view.bounds);
    return CGRectIsNull(covered) ? 0 : CGRectGetMaxY(covered);
}

static void Attach(UIViewController *host) {
    if (!host.isViewLoaded) return;
    HKTWebViewController *web = objc_getAssociatedObject(host, WebKey);
    if (!web) {
        __weak UIViewController *weakHost = host;
        web = [[HKTWebViewController alloc] initWithHomeURL:[NSURL URLWithString:@HKT_SITE_URL]
            openVideo:^(NSString *videoID) { OpenVideo(weakHost, videoID); }
            openExternal:^(NSURL *url) { [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil]; }];
        web.coveredTop = ^CGFloat(UIView *view) { return CoveredTop(weakHost, view); };
        objc_setAssociatedObject(host, WebKey, web, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [host addChildViewController:web];
        web.view.frame = host.view.bounds;
        web.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host.view addSubview:web.view];
        [web didMoveToParentViewController:host];
    }
    // The app re-adds its own response view on top whenever it prepares a request (-[YTWrapperView setChildView:]).
    [host.view bringSubviewToFront:web.view];
}

// Every request a browse page makes (first load, refresh, retry) goes through this method, and the
// responses it delivers are the only source of the native feed, so Home never loads one.
static void Request(id self, SEL _cmd, BOOL refresh, BOOL disablePrepare, BOOL nonContinuation) {
    if (IsHome(self)) {
        Attach(self);
        return;
    }
    ((void (*)(id, SEL, BOOL, BOOL, BOOL))OriginalRequest)(self, _cmd, refresh, disablePrepare, nonContinuation);
}

static void Appear(id self, SEL _cmd, BOOL animated) {
    ((void (*)(id, SEL, BOOL))OriginalAppear)(self, _cmd, animated);
    if (IsHome(self)) Attach(self);
}

BOOL HKTHomeSupported(void) {
    Class browse = NSClassFromString(@"YTBrowseViewController");
    Class events = NSClassFromString(@"YTAccountScopedCommandResponderEvent");
    Protocol *shape = @protocol(HKTBrowseViewController);
    // Walked with the runtime: this runs while the library loads, and a message to the class
    // would run the app's +initialize methods before its main().
    Class ancestor = browse;
    while (ancestor && ancestor != UIViewController.class) ancestor = class_getSuperclass(ancestor);
    return ancestor
        && HKTMethod(browse, shape, @selector(browseIdentifier), YES)
        && HKTMethod(browse, shape, @selector(viewWillAppear:), YES)
        && HKTMethod(browse, shape, @selector(makeRequestForRefresh:disablePrepareToRefresh:nonContinuationRefresh:), YES)
        && HKTMethod(NSClassFromString(@"YTICommand"), @protocol(HKTCommand), @selector(watchNavigationEndpointWithVideoID:), NO)
        && HKTMethod(events, @protocol(HKTCommandEvent), @selector(eventForActiveIdentityInGlobalScopeWithCommand:fromView:entry:sendClick:firstResponder:), NO)
        && HKTMethod(events, @protocol(HKTCommandEvent), @selector(send), YES);
}

BOOL HKTInstallHome(void) {
    if (OriginalRequest) return YES;
    if (!HKTHomeSupported()) return NO;
    Class browse = NSClassFromString(@"YTBrowseViewController");
    Protocol *shape = @protocol(HKTBrowseViewController);
    HeaderKnown = HKTMethod(NSClassFromString(@"YTHeaderContentComboView"), @protocol(HKTHeaderContentComboView), @selector(headerView), YES) != NULL;
    HKTReplace(browse, shape, @selector(makeRequestForRefresh:disablePrepareToRefresh:nonContinuationRefresh:), YES, (IMP)Request, &OriginalRequest);
    HKTReplace(browse, shape, @selector(viewWillAppear:), YES, (IMP)Appear, &OriginalAppear);
    return YES;
}
