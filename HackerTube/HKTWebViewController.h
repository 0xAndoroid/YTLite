#import <UIKit/UIKit.h>

/// Shows the site at one URL and keeps the web view on that site. An activated watch link goes to
/// `openVideo`, an activated link to another site goes to `openExternal`, and a load that fails or
/// is answered with an HTTP error status is replaced by a message with a Retry button.
@interface HKTWebViewController : UIViewController

- (instancetype)initWithHomeURL:(NSURL *)homeURL
                      openVideo:(void (^)(NSString *videoID))openVideo
                   openExternal:(void (^)(NSURL *url))openExternal NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(NSString *)name bundle:(NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// Height at the top of the given view that the host's own bars cover. Optional.
@property (nonatomic, copy) CGFloat (^coveredTop)(UIView *view);

@end
