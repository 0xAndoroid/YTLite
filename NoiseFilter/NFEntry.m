#import "NFHome.h"
#import "NFRuntime.h"
#import "NFService.h"
#import "NFSettingsViewController.h"
#import <objc/message.h>
#import <os/log.h>

static __weak NFService *Service;
static IMP OriginalSettingsAppearance;
static const void *EntryKey = &EntryKey;

static void SettingsAppeared(UIViewController *controller, SEL selector, BOOL animated) {
    ((void (*)(id, SEL, BOOL))OriginalSettingsAppearance)(controller, selector, animated);
    if (!NSThread.isMainThread || !Service) return;
    UIBarButtonItem *button = objc_getAssociatedObject(controller, EntryKey);
    if (!button) {
        __weak UIViewController *weakController = controller;
        UIAction *action = [UIAction actionWithHandler:^(UIAction *action) {
            UIViewController *owner = weakController;
            NFService *service = Service;
            if (!owner || !service) return;
            NFSettingsViewController *settings = [[NFSettingsViewController alloc] initWithService:service];
            ((void (*)(id, SEL, id))objc_msgSend)(owner, @selector(showOrPushViewController:), settings);
        }];
        action.title = @"Noise filter";
        button = [[UIBarButtonItem alloc] initWithPrimaryAction:action];
        button.accessibilityIdentifier = @"noise-filter.settings";
        objc_setAssociatedObject(controller, EntryKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSArray *existing = controller.navigationItem.rightBarButtonItems ?: @[];
    if (![existing containsObject:button]) controller.navigationItem.rightBarButtonItems = [existing arrayByAddingObject:button];
}

BOOL NFInstallSettingsHooks(NFService *service) {
    if (OriginalSettingsAppearance) return YES;
    Class cls = NSClassFromString(@"YTSettingsViewController");
    if (!NSThread.isMainThread || !service ||
        !NFMethodMatches(cls, @selector(viewDidAppear:), "v20@0:8B16") ||
        !NFMethodMatches(cls, @selector(showOrPushViewController:), "v24@0:8@16")) return NO;
    Service = service;
    OriginalSettingsAppearance = NFHook(cls, @selector(viewDidAppear:), "v20@0:8B16", (IMP)SettingsAppeared);
    return OriginalSettingsAppearance != NULL;
}

#ifndef NF_TESTING
static void Start(void) {
    NFService *service = NFService.shared;
    if (!service) return;
    if (!NFInstallSettingsHooks(service)) os_log_error(OS_LOG_DEFAULT, "NoiseFilter: Settings ABI unavailable");
    if (!NFInstallHomeHooks(service)) os_log_error(OS_LOG_DEFAULT, "NoiseFilter: Home ABI unavailable");
}
__attribute__((constructor)) static void Install(void) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSString *name in @[UIApplicationDidFinishLaunchingNotification, UIApplicationProtectedDataDidBecomeAvailable]) {
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { Start(); }];
    }
    dispatch_async(dispatch_get_main_queue(), ^{ Start(); });
}
#endif
