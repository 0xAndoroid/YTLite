#import "HKTWebViewController.h"
#import "HKTRoute.h"
#import <WebKit/WebKit.h>

// hackertube.org follows same-site links in a document-level click handler (history.pushState), so
// a tap on a card never reaches the navigation delegate. Registered at document start, this
// listener runs before that handler and withholds watch links from it; the link's default
// navigation then reaches -webView:decidePolicyForNavigationAction:. Controls inside a card that
// stop the event (the Watch later button) never get here.
static NSString *const WatchLinkScript =
    @"document.addEventListener('click', (event) => {"
     "  const link = event.target instanceof Element && event.target.closest('a[href]');"
     "  if (!link || event.defaultPrevented) return;"
     "  if (link.origin === location.origin && /^\\/watch(\\/|$)/.test(link.pathname)) event.stopImmediatePropagation();"
     "});";

@interface HKTWebViewController () <WKNavigationDelegate>
@end

@implementation HKTWebViewController {
    NSURL *_homeURL;
    void (^_openVideo)(NSString *videoID);
    void (^_openExternal)(NSURL *url);
    WKWebView *_webView;
    WKNavigation *_homeLoad;
    UIStackView *_failure;
    UILabel *_reason;
}

- (instancetype)initWithHomeURL:(NSURL *)homeURL
                      openVideo:(void (^)(NSString *videoID))openVideo
                   openExternal:(void (^)(NSURL *url))openExternal {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _homeURL = homeURL;
        _openVideo = [openVideo copy];
        _openExternal = [openExternal copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    // The default configuration keeps the persistent data store, where the site saves its state.
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    [configuration.userContentController addUserScript:[[WKUserScript alloc]
        initWithSource:WatchLinkScript injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    _webView.navigationDelegate = self;
    // Until the page paints, the view behind shows instead of WebKit's white.
    _webView.opaque = NO;
    _webView.backgroundColor = UIColor.clearColor;
    // A link preview would render the site's own watch page.
    _webView.allowsLinkPreview = NO;
    [self.view addSubview:_webView];

    UILabel *title = [UILabel new];
    title.text = @"HackerTube could not be loaded.";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _reason = [UILabel new];
    _reason.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _reason.textColor = UIColor.secondaryLabelColor;
    for (UILabel *label in @[title, _reason]) {
        label.numberOfLines = 0;
        label.textAlignment = NSTextAlignmentCenter;
        label.adjustsFontForContentSizeCategory = YES;
    }
    UIButton *retry = [UIButton buttonWithType:UIButtonTypeSystem];
    [retry setTitle:@"Retry" forState:UIControlStateNormal];
    retry.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    retry.accessibilityIdentifier = @"hackertube.retry";
    [retry addTarget:self action:@selector(loadHome) forControlEvents:UIControlEventPrimaryActionTriggered];

    _failure = [[UIStackView alloc] initWithArrangedSubviews:@[title, _reason, retry]];
    _failure.axis = UILayoutConstraintAxisVertical;
    _failure.alignment = UIStackViewAlignmentCenter;
    _failure.spacing = 12;
    _failure.accessibilityIdentifier = @"hackertube.failure";
    _failure.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_failure];
    UILayoutGuide *margins = self.view.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_failure.centerYAnchor constraintEqualToAnchor:margins.centerYAnchor],
        [_failure.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_failure.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
    ]];

    [self loadHome];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets insets = self.view.safeAreaInsets;
    if (self.coveredTop) insets.top = MAX(insets.top, self.coveredTop(self.view));
    _webView.frame = UIEdgeInsetsInsetRect(self.view.bounds, insets);
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self.view setNeedsLayout];
}

- (void)loadHome {
    _failure.hidden = YES;
    _webView.hidden = NO;
    _homeLoad = [_webView loadRequest:[NSURLRequest requestWithURL:_homeURL]];
}

- (void)showFailure:(NSString *)reason {
    _homeLoad = nil;
    _reason.text = reason;
    _webView.hidden = YES;
    _failure.hidden = NO;
}

- (void)navigation:(WKNavigation *)navigation failedWithError:(NSError *)error {
    // Only the current home load can fail the page. WebKit reports a load that was cancelled here
    // once more as an error, which can arrive after Retry has started the next load, and a link
    // whose navigation fails leaves the page it was on.
    if (navigation != _homeLoad) return;
    // A load that a newer navigation replaced is not a failure.
    if ([error.domain isEqual:NSURLErrorDomain] && error.code == NSURLErrorCancelled) return;
    [self showFailure:error.localizedDescription];
}

#pragma mark WKNavigationDelegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    BOOL newWindow = action.targetFrame == nil;
    if (!newWindow && !action.targetFrame.isMainFrame) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }
    // Only a link activation opens the player or leaves the app; a redirect, a refresh or a script
    // navigation does neither. WebKit also reports a click() that the page's own script makes on a
    // link as an activation, so this is not proof of a touch.
    BOOL activated = action.navigationType == WKNavigationTypeLinkActivated;
    NSString *videoID;
    switch (HKTRouteForURL(action.request.URL, _homeURL, &videoID)) {
        case HKTRouteInSite:
            if (newWindow) [webView loadRequest:action.request];
            decisionHandler(newWindow ? WKNavigationActionPolicyCancel : WKNavigationActionPolicyAllow);
            return;
        case HKTRouteVideo:
            if (activated) _openVideo(videoID);
            break;
        case HKTRouteExternal:
            if (activated) _openExternal(action.request.URL);
            break;
        case HKTRouteBlocked:
            break;
    }
    decisionHandler(WKNavigationActionPolicyCancel);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse
    decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)navigationResponse.response;
    if (navigationResponse.isForMainFrame && [response isKindOfClass:NSHTTPURLResponse.class] && response.statusCode >= 400) {
        // WebKit would otherwise show the server's error page as a page that loaded.
        [self showFailure:[NSString stringWithFormat:@"The site answered with HTTP status %ld (%@).",
            (long)response.statusCode, [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode]]];
        decisionHandler(WKNavigationResponsePolicyCancel);
        return;
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self navigation:navigation failedWithError:error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self navigation:navigation failedWithError:error];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [self loadHome];
}

@end
