// YTLiteUnlock: bypass the defunct YTLite 5.2.1 Patreon settings gate.
//
// Binary check, release v5.2.1 arm64:
//   - YTPAPIHelper does not implement the access-check selector; its only class method is
//     fetchChannelImageWithChannelID:completion:.
//   - YTLite already hooks that access-check selector elsewhere and grants it.
//   - The Patreon lock is in YTPSettingsBuilder: rootTable can route to thanksTable
//     (logged-out/supporter UI) instead of prefsTable (full settings).

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

typedef id (*YTLiteUnlockObjectMessageSend)(id, SEL);

static id YTLiteUnlockPrefsTable(id self) {
    SEL prefsTableSelector = sel_registerName("prefsTable");
    return ((YTLiteUnlockObjectMessageSend)objc_msgSend)(self, prefsTableSelector);
}

static id YTLiteUnlockSettingsTable(id self, SEL _cmd) {
    return YTLiteUnlockPrefsTable(self);
}

static void YTLiteUnlockSupportersViewDidLoad(UIViewController *self, SEL _cmd) {
    UIViewController *presentedController = self.navigationController ?: self;
    UIViewController *presentingController = presentedController.presentingViewController ?: self.presentingViewController;
    [presentingController dismissViewControllerAnimated:NO completion:nil];
}

static BOOL YTLiteUnlockReplaceInstanceMethod(Class cls, SEL selector, IMP replacement) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        return NO;
    }

    IMP current = method_getImplementation(method);
    if (current != replacement) {
        method_setImplementation(method, replacement);
    }

    return YES;
}

static BOOL YTLiteUnlockInstallSettingsGateBypass(void) {
    Class builderClass = objc_getClass("YTPSettingsBuilder");
    if (!builderClass) {
        return NO;
    }

    SEL prefsTableSelector = sel_registerName("prefsTable");
    if (!class_getInstanceMethod(builderClass, prefsTableSelector)) {
        return NO;
    }

    BOOL installedRootTable = YTLiteUnlockReplaceInstanceMethod(
        builderClass,
        sel_registerName("rootTable"),
        (IMP)YTLiteUnlockSettingsTable
    );

    BOOL installedThanksTable = YTLiteUnlockReplaceInstanceMethod(
        builderClass,
        sel_registerName("thanksTable"),
        (IMP)YTLiteUnlockSettingsTable
    );

    return installedRootTable && installedThanksTable;
}

static BOOL YTLiteUnlockInstallSupportersFallback(void) {
    Class supportersClass = objc_getClass("DVNSupportersVC");
    if (!supportersClass) {
        return NO;
    }

    return YTLiteUnlockReplaceInstanceMethod(
        supportersClass,
        sel_registerName("viewDidLoad"),
        (IMP)YTLiteUnlockSupportersViewDidLoad
    );
}

static void YTLiteUnlockInstallAttempt(NSUInteger attempt) {
    BOOL installedSettingsGateBypass = YTLiteUnlockInstallSettingsGateBypass();
    BOOL installedSupportersFallback = YTLiteUnlockInstallSupportersFallback();

    static const NSUInteger minimumRefreshAttempts = 12;
    static const NSUInteger maximumAttempts = 24;
    BOOL keepRefreshing = attempt < minimumRefreshAttempts;
    BOOL missingHook = !installedSettingsGateBypass || !installedSupportersFallback;

    if ((keepRefreshing || missingHook) && attempt + 1 < maximumAttempts) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            YTLiteUnlockInstallAttempt(attempt + 1);
        });
    }
}

__attribute__((constructor))
static void YTLiteUnlockConstructor(void) {
    @autoreleasepool {
        NSLog(@"[YTLiteUnlock] bypassing YTLite 5.2.1 Patreon settings gate.");
        YTLiteUnlockInstallAttempt(0);
    }
}
