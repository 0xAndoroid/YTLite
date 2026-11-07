#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "NFHome.h"
#import "NFService.h"
#import "NFSettingsViewController.h"

static UIWindow *Window;
static void Screenshot(NSString *name) {
    [Window layoutIfNeeded];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:Window.bounds];
    NSData *png = [renderer PNGDataWithActions:^(UIGraphicsImageRendererContext *context) {
        [Window drawViewHierarchyInRect:Window.bounds afterScreenUpdates:YES];
    }];
    NSString *file = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:name];
    [png writeToFile:file atomically:YES];
}
static void Check(BOOL passed, NSString *message) {
    if (passed) return;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    if (Window) Screenshot(@"failure.png");
    exit(1);
}
static void Wait(BOOL (^ready)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!ready() && end.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    Check(ready(), @"Expected UIKit event did not finish");
}

static NSData *Key;
static OSStatus WriteStatus;
static void CheckKeyQuery(CFDictionaryRef query) {
    NSDictionary *item = (__bridge NSDictionary *)query;
    Check([item[(__bridge id)kSecAttrService] isEqual:@"noise-filter-uikit-fixture"], @"Unexpected Keychain service");
    Check([item[(__bridge id)kSecAttrAccount] isEqual:@"typesafe-api-key"], @"Unexpected Keychain account");
}
OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    CheckKeyQuery(query);
    if (!Key) return errSecItemNotFound;
    if (result) *result = CFBridgingRetain(Key);
    return errSecSuccess;
}
OSStatus SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributes) {
    CheckKeyQuery(query);
    if (WriteStatus) return WriteStatus;
    if (!Key) return errSecItemNotFound;
    Key = [(__bridge NSDictionary *)attributes objectForKey:(__bridge id)kSecValueData];
    return errSecSuccess;
}
OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    CheckKeyQuery(attributes);
    if (WriteStatus) return WriteStatus;
    NSDictionary *item = (__bridge NSDictionary *)attributes;
    Check([item[(__bridge id)kSecAttrAccessible] isEqual:(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly], @"Key accessibility changed");
    Key = item[(__bridge id)kSecValueData];
    return errSecSuccess;
}
OSStatus SecItemDelete(CFDictionaryRef query) {
    CheckKeyQuery(query);
    if (WriteStatus) return WriteStatus;
    Key = nil;
    return errSecSuccess;
}
@interface NoNetwork : NSURLProtocol
@end
@implementation NoNetwork
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading { Check(NO, @"UI/identity diagnostics unexpectedly issued a network request"); }
- (void)stopLoading {}
@end

@interface YTSettingsViewController : UIViewController
- (void)showOrPushViewController:(UIViewController *)controller;
@end
@implementation YTSettingsViewController
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; }
- (void)showOrPushViewController:(UIViewController *)controller { [self.navigationController pushViewController:controller animated:NO]; }
@end

@interface ELMElement : NSObject
- (NSString *)protoText;
@end
@implementation ELMElement
- (NSString *)protoText {
    return [@"video_id: \"AAAAAAAAAA1\"\nurl: \"https://www.youtube.com/watch?v=AAAAAAAAAA1&token=fixture-private\"\ntracking: \"fixture-private\"\ntruncated: \""
        stringByAppendingString:[@"fixture-private" stringByPaddingToLength:40000 withString:@"fixture-private" startingAtIndex:0]];
}
@end
@interface FixtureNode : NSObject
@property ELMElement *element;
@end
@implementation FixtureNode
@end
@interface FixtureRenderer : NSObject
@property NSString *videoId;
@end
@implementation FixtureRenderer
@end
@interface FixtureCellController : NSObject
@property FixtureRenderer *entry;
@end
@implementation FixtureCellController
@end
@interface YTSectionController : NSObject
@property NSArray *items;
- (id)cellControllerAtIndex:(NSInteger)index;
@end
@implementation YTSectionController
- (id)cellControllerAtIndex:(NSInteger)index { return self.items[index]; }
@end
@interface YTSectionListViewController : NSObject
@property BOOL isHomeFeed;
@end
@implementation YTSectionListViewController
@end
@interface FixtureCell : UICollectionViewCell
@property FixtureNode *node;
@end
@implementation FixtureCell
@end
@interface YTInnerTubeCollectionViewController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property YTSectionListViewController *delegate;
@property UICollectionView *collectionView;
@property YTSectionController *section;
@property NSUInteger displays;
- (NSIndexPath *)modelIndexPathForPresentationIndexPath:(NSIndexPath *)index;
- (BOOL)isValidIndexPath:(NSIndexPath *)index;
- (YTSectionController *)sectionControllerAtIndexPath:(NSIndexPath *)index;
@end
@implementation YTInnerTubeCollectionViewController
- (void)loadView {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.itemSize = CGSizeMake(320, 180);
    layout.minimumLineSpacing = 12;
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:FixtureCell.class forCellWithReuseIdentifier:@"video"];
    self.view = self.collectionView;
}
- (NSInteger)collectionView:(UICollectionView *)collection numberOfItemsInSection:(NSInteger)section { return self.section.items.count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)collection cellForItemAtIndexPath:(NSIndexPath *)index {
    FixtureCell *cell = [collection dequeueReusableCellWithReuseIdentifier:@"video" forIndexPath:index];
    cell.backgroundColor = index.item % 2 ? UIColor.systemTealColor : UIColor.systemOrangeColor;
    cell.node = [FixtureNode new];
    cell.node.element = [ELMElement new];
    return cell;
}
- (void)collectionView:(UICollectionView *)collection willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)index { self.displays++; }
- (NSIndexPath *)modelIndexPathForPresentationIndexPath:(NSIndexPath *)index { return index; }
- (BOOL)isValidIndexPath:(NSIndexPath *)index { return index.section == 0 && index.item < self.section.items.count; }
- (YTSectionController *)sectionControllerAtIndexPath:(NSIndexPath *)index { return self.section; }
@end

static IMP OriginalAlertAction, OriginalUIAction;
static const void *HandlerKey = &HandlerKey;
static NSMutableArray *Actions;
static id AlertAction(id self, SEL selector, NSString *title, UIAlertActionStyle style, void (^handler)(UIAlertAction *)) {
    id action = ((id (*)(id, SEL, id, UIAlertActionStyle, id))OriginalAlertAction)(self, selector, title, style, handler);
    objc_setAssociatedObject(action, HandlerKey, handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return action;
}
static id Action(id self, SEL selector, void (^handler)(UIAction *)) {
    id action = ((id (*)(id, SEL, id))OriginalUIAction)(self, selector, handler);
    objc_setAssociatedObject(action, HandlerKey, handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [Actions addObject:action];
    return action;
}
static void Select(NFSettingsViewController *settings, NSInteger section, NSInteger row) {
    [settings tableView:settings.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
}
static void EnterKey(NFSettingsViewController *settings, NSString *value) {
    Select(settings, 1, 0);
    Wait(^BOOL { return [settings.presentedViewController isKindOfClass:UIAlertController.class]; });
    UIAlertController *alert = (UIAlertController *)settings.presentedViewController;
    Check(alert.textFields.count == 1 && alert.textFields.firstObject.secureTextEntry, @"The key field must be secure");
    alert.textFields.firstObject.text = value;
    for (UIAlertAction *action in alert.actions) if ([action.title isEqual:@"Save"]) {
        void (^handler)(UIAlertAction *) = objc_getAssociatedObject(action, HandlerKey);
        Check(handler != nil, @"The displayed Save action has no handler");
        handler(action);
    }
    [settings dismissViewControllerAnimated:NO completion:nil];
    Wait(^BOOL { return settings.presentedViewController == nil; });
}
static UITableViewCell *Row(NFSettingsViewController *settings, NSInteger section, NSInteger row) {
    return [settings tableView:settings.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
}
static void RunChecks(void) {
    NSString *domain = [@"noise-filter-uikit." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *store = [[NSUserDefaults alloc] initWithSuiteName:domain];
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.protocolClasses = @[NoNetwork.class];
    NFService *service = [[NFService alloc] initWithDefaults:store configuration:configuration keyService:@"noise-filter-uikit-fixture"];
    Check(service != nil, @"The production service did not initialize");
    Method appearance = class_getInstanceMethod(UIViewController.class, @selector(viewDidAppear:));
    IMP baseAppearance = method_getImplementation(appearance);
    Check(NFInstallHomeHooks(service) && NFInstallSettingsHooks(service), @"The actual hook installer rejected the fixture ABI");
    Check(method_getImplementation(appearance) == baseAppearance, @"Hooks changed a shared UIKit superclass");
    Actions = [NSMutableArray new];
    Method alertFactory = class_getClassMethod(UIAlertAction.class, @selector(actionWithTitle:style:handler:));
    Method actionFactory = class_getClassMethod(UIAction.class, @selector(actionWithHandler:));
    OriginalAlertAction = method_setImplementation(alertFactory, (IMP)AlertAction);
    OriginalUIAction = method_setImplementation(actionFactory, (IMP)Action);

    YTSettingsViewController *nativeSettings = [YTSettingsViewController new];
    UIBarButtonItem *originalItem = [[UIBarButtonItem alloc] initWithTitle:@"Existing" style:UIBarButtonItemStylePlain target:nil action:NULL];
    nativeSettings.navigationItem.rightBarButtonItem = originalItem;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:nativeSettings];
    Window.rootViewController = navigation;
    [Window makeKeyAndVisible];
    Wait(^BOOL { return nativeSettings.navigationItem.rightBarButtonItems.count == 2; });
    Check(nativeSettings.navigationItem.rightBarButtonItems.firstObject == originalItem, @"The Settings entry replaced an existing control");
    UIAction *entry;
    for (UIAction *action in Actions) if ([action.title isEqual:@"Noise filter"]) entry = action;
    Check(entry != nil, @"The Settings entry was not created");
    void (^entryHandler)(UIAction *) = objc_getAssociatedObject(entry, HandlerKey);
    entryHandler(entry);
    Wait(^BOOL { return [navigation.topViewController isKindOfClass:NFSettingsViewController.class] && navigation.topViewController.view.window != nil; });
    NFSettingsViewController *settings = (NFSettingsViewController *)navigation.topViewController;
    Check(settings.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark, @"The tested Settings view is not in the requested dark appearance");
    EnterKey(settings, @"fixture-key");
    Check(service.hasKey && [Key isEqual:[@"fixture-key" dataUsingEncoding:NSUTF8StringEncoding]], @"The UIKit Save action did not reach the service's Keychain adapter");
    Check([((UIListContentConfiguration *)Row(settings, 1, 0).contentConfiguration).secondaryText isEqual:@"Saved"], @"Key save is not shown");
    WriteStatus = errSecAuthFailed;
    EnterKey(settings, @"fixture-replacement");
    Check([Key isEqual:[@"fixture-key" dataUsingEncoding:NSUTF8StringEncoding]] &&
          [((UIListContentConfiguration *)Row(settings, 1, 0).contentConfiguration).secondaryText containsString:@"unchanged"], @"A failed key save did not preserve/report the original key");
    WriteStatus = errSecSuccess;
    Select(settings, 1, 1);
    Check(!Key && !service.hasKey, @"The Remove key action did not remove its own item");
    EnterKey(settings, @"fixture-key");

    UISwitch *enabled = (UISwitch *)Row(settings, 0, 0).accessoryView;
    enabled.on = NO;
    [enabled sendActionsForControlEvents:UIControlEventValueChanged];
    Check(!service.enabled, @"The enabled control did not save");
    enabled.on = YES;
    [enabled sendActionsForControlEvents:UIControlEventValueChanged];
    NSInteger noiseIndex = [service.contract.categoryNames indexOfObject:@"noise"];
    UISwitch *category = (UISwitch *)Row(settings, 2, noiseIndex).accessoryView;
    category.on = NO;
    [category sendActionsForControlEvents:UIControlEventValueChanged];
    Select(settings, 3, [service.contract.strictnessNames indexOfObject:@"strict"]);
    Check(![service.settings[@"categories"][@"noise"] boolValue] && [service.settings[@"strictness"] isEqual:@"strict"], @"Category or strictness action did not save");
    NSIndexPath *instructionsIndex = [NSIndexPath indexPathForRow:0 inSection:4];
    [settings.tableView scrollToRowAtIndexPath:instructionsIndex atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    [settings.tableView layoutIfNeeded];
    UITableViewCell *instructionsRow = [settings.tableView cellForRowAtIndexPath:instructionsIndex];
    UITextView *instructions;
    for (UIView *view in instructionsRow.contentView.subviews) if ([view isKindOfClass:UITextView.class]) instructions = (UITextView *)view;
    Check(instructions != nil && instructions.window != nil, @"Instructions editor missing from the rendered row");
    instructions.text = @"  Hide fixture videos.  ";
    Select(settings, 4, 1);
    Check([service.instructions isEqual:@"Hide fixture videos."], @"Save instructions did not apply the shared contract");
    Screenshot(@"instructions.png");
    NFService *reopened = [[NFService alloc] initWithDefaults:store configuration:configuration keyService:@"noise-filter-uikit-fixture"];
    Check(reopened.enabled && reopened.hasKey && [reopened.settings isEqual:service.settings] && [reopened.instructions isEqual:service.instructions], @"Settings/key did not survive a new service instance");
    NSString *cacheKey = [NSString stringWithFormat:@"v:%@:AAAAAAAAAA1", service.verdictNamespace];
    [store setObject:[NSJSONSerialization dataWithJSONObject:@{@"scores": @{@"noise": @1}} options:0 error:nil] forKey:cacheKey];
    Select(settings, 5, 0);
    Check(![service verdictForVideo:@"AAAAAAAAAA1"] && service.hasKey, @"Clear judgments affected the key or left a cached judgment");
    Screenshot(@"settings.png");

    YTInnerTubeCollectionViewController *home = [YTInnerTubeCollectionViewController new];
    home.delegate = [YTSectionListViewController new];
    home.delegate.isHomeFeed = YES;
    home.section = [YTSectionController new];
    NSMutableArray *items = [NSMutableArray new];
    for (NSUInteger i = 0; i < 8; i++) {
        FixtureCellController *item = [FixtureCellController new];
        item.entry = [FixtureRenderer new];
        item.entry.videoId = [NSString stringWithFormat:@"AAAAAAAAAA%lu", (unsigned long)i];
        [items addObject:item];
    }
    home.section.items = items;
    Select(settings, 5, 1);
    Window.rootViewController = home;
    Wait(^BOOL { return [NFHomeDiagnostics()[@"observations"] count] > 0; });
    Check(home.displays > 0 && [home.collectionView numberOfItemsInSection:0] == 8, @"Capture replaced the native display handler or changed item counts");
    CGRect first = [home.collectionView layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]].frame;
    Check(first.size.height == 180 && first.size.width == 320, @"Diagnostics changed a native row's size");
    [home.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:7 inSection:0] atScrollPosition:UICollectionViewScrollPositionBottom animated:NO];
    [home.collectionView layoutIfNeeded];
    Wait(^BOOL { return [NFHomeDiagnostics()[@"observations"] count] == 8; });
    Screenshot(@"home-diagnostic.png");
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSData *saved = [NSData dataWithContentsOfFile:[documents stringByAppendingPathComponent:@"NoiseFilter-diagnostics.json"]];
    NSString *json = [[NSString alloc] initWithData:saved encoding:NSUTF8StringEncoding];
    Check([json containsString:@"AAAAAAAAAA1"] && [json containsString:@"<redacted>"] &&
          ![json containsString:@"fixture-private"] && ![json containsString:@"fixture-key"], @"Home export lost identity or leaked a key/private/truncated string");
    [saved writeToFile:[documents stringByAppendingPathComponent:@"home-diagnostics.json"] atomically:YES];
    NSUInteger calls = [NFHomeDiagnostics()[@"homeDisplayCallbacks"] unsignedIntegerValue];
    home.delegate.isHomeFeed = NO;
    [home collectionView:home.collectionView willDisplayCell:home.collectionView.visibleCells.firstObject forItemAtIndexPath:home.collectionView.indexPathsForVisibleItems.firstObject];
    Check([NFHomeDiagnostics()[@"homeDisplayCallbacks"] unsignedIntegerValue] == calls, @"A non-Home callback was recorded as Home");
    Check(![service.diagnostics[@"requests"] unsignedIntegerValue], @"An identity capture admitted an inference request");
    Window.rootViewController = [UIViewController new];
    method_setImplementation(alertFactory, OriginalAlertAction);
    method_setImplementation(actionFactory, OriginalUIAction);
    [service saveKey:@""];
    [store removePersistentDomainForName:domain];
    puts("NoiseFilter UIKit: PASS (Settings and observational Home hooks; stand-in YouTube classes, fake Keychain, no network; NOT filtering acceptance)");
}
@interface NFTestScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation NFTestScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    Window = self.window;
    Window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    Window.rootViewController = [UIViewController new];
    [Window makeKeyAndVisible];
    // A timer callback permits the fixture's nested run loop to service main-queue completions.
    [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) { RunChecks(); exit(0); }];
}
@end
@interface NFTestApp : UIResponder <UIApplicationDelegate>
@end
@implementation NFTestApp
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(NFTestApp.class)); } }
