#import <UIKit/UIKit.h>

/// Shows the site at one URL and keeps the web view on that site. Watch links go to `openVideo`,
/// tapped links to other sites go to `openExternal`, and a failed load is replaced by a message
/// with a Retry button.
@interface HKTWebViewController : UIViewController

- (instancetype)initWithHomeURL:(NSURL *)homeURL
                      openVideo:(void (^)(NSString *videoID))openVideo
                   openExternal:(void (^)(NSURL *url))openExternal NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(NSString *)name bundle:(NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// Height at the top of the given view that the host's own bars cover. Optional.
@property (nonatomic, copy) CGFloat (^coveredTop)(UIView *view);

@end
