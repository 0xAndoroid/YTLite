// YTLiteUnlock — runtime neutralization of the defunct YTLite 5.2.1 Patreon activation gate.
//
// Ground truth (class-dump / nm / otool / strings of the real 5.2.1 dylib extracted from
// com.dvntm.ytlite_5.2.1_iphoneos-arm64.deb, fetched from dayanch96/YTLite release v5.2.1):
//
//   @interface YTPAPIHelper : NSObject
//   + (void)verifyAccessWithCompletion:(void (^)(BOOL granted, NSError *error))completion;
//   @end
//     - sole method on the class (1 entry in its class method list)
//     - encoded type: v32@0:8@16@?24  (void, self, SEL, id arg1=block)
//     - selector string present in __objc_methname: "verifyAccessWithCompletion:"
//     - implementation @0x1b7128: obfuscated — XOR-decrypts HTTP strings (POST, context,
//       application/json, Content-Type, server URL) at runtime, holds an atomic one-shot
//       latch at 0x1207b64, and hits a now-dead licensing server.
//
//   @interface DVNSupportersVC : UIViewController <WKNavigationDelegate>
//   - (void)viewDidLoad;                                   v16@0:8
//   - (void)webView:didStartProvisionalNavigation:;       v32@0:8@16@24
//   - (void)webView:didFinishNavigation:;                 v32@0:8@16@24
//   - (void)webView:didFailProvisionalNavigation:withError:; v40@0:8@16@24@32
//   - (void).cxx_destruct;                                 v16@0:8
//   @end
//     - the supporters/purchase webview shown when access is denied.
//
// The completion block's exact arity is obfuscated behind a jump table; the deny-path block
// invoke (@0xba4ac) tests its argument for nil. To be robust to void(^)(BOOL),
// void(^)(NSError*), or void(^)(BOOL, NSError*), we invoke completion(YES, nil): under the
// ARM64/AAPCS calling convention extra arguments are harmlessly ignored, and (YES, nil)
// means "granted, no error" in every plausible encoding.
//
// The gate is NOT in a static initializer (__init_offsets was inspected; 0x1b7128's caller
// at 0xb82e8 is not among the ctor entries), so it fires at app/settings runtime — after all
// injected tweak dylibs are loaded by dyld. The %hook therefore installs before the gate runs.
// As a guard against the theoretical case where YTLite.dylib loads after this unlock dylib
// (class not yet registered), %init is retried from +load via a short async hop.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

typedef void (^YTPAccessCompletion)(BOOL granted, NSError *error);

@interface YTPAPIHelper : NSObject
@end

@interface DVNSupportersVC : UIViewController
@end

%hook YTPAPIHelper

+ (void)verifyAccessWithCompletion:(YTPAccessCompletion)completion {
    // Grant immediately; skip the dead licensing server entirely.
    if (completion) completion(YES, nil);
}

%end

// Defense-in-depth: if anything still allocates/presents DVNSupportersVC (a second call site,
// cached state, or a re-check), dismiss it instead of showing the dead purchase webview.
%hook DVNSupportersVC

- (void)viewDidLoad {
    %orig;
    if (self.presentingViewController) {
        [self.presentingViewController dismissViewControllerAnimated:NO completion:nil];
    }
}

%end

static void YTLiteUnlockInstall(void) {
    // %hook uses Logos late binding; %init resolves classes via objc_getClass at call time.
    // Retry covers the load-order edge case where YTLite.dylib registers the gate classes
    // after this dylib's first %ctor pass.
    %init;
    if (!objc_getClass("YTPAPIHelper") || !objc_getClass("DVNSupportersVC")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ YTLiteUnlockInstall(); });
    }
}

%ctor {
    @autoreleasepool {
        NSLog(@"[YTLiteUnlock] neutralizing defunct 5.2.1 activation gate.");
        YTLiteUnlockInstall();
    }
}
