#import <Foundation/Foundation.h>

typedef void (^NFHTTPReply)(NSData *, NSHTTPURLResponse *);
@interface NFHTTP : NSObject <NSURLSessionDataDelegate>
- (instancetype)initWithConfiguration:(NSURLSessionConfiguration *)configuration;
- (void)invalidate;
- (void)request:(NSURLRequest *)request limit:(NSUInteger)limit player:(BOOL)player reply:(NFHTTPReply)reply;
@end
