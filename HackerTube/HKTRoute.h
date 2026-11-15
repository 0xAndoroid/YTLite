#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, HKTRoute) {
    /// Stays in the web view.
    HKTRouteInSite,
    /// A watch link with a well-formed video id: plays in the app.
    HKTRouteVideo,
    /// Another web site.
    HKTRouteExternal,
    /// A watch link without a well-formed video id, or a scheme other than http(s).
    HKTRouteBlocked,
};

/// Where a link or navigation to `url` goes when the web view shows the site at `home`.
/// `videoID` is set only for HKTRouteVideo.
HKTRoute HKTRouteForURL(NSURL *url, NSURL *home, NSString **videoID);
