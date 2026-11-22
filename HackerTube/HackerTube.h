#import <UIKit/UIKit.h>
#import <objc/runtime.h>

/// Standard user defaults key of the "HackerTube Home" switch. Read once per launch.
extern NSString *const HKTHomeEnabledKey;
extern NSString *const HKTAllowShortsPiPKey;
void HKTInstallShortsPiP(void);

/// The method `cls` responds to for `selector`, provided its type encoding is the one the
/// protocol `shape` declares for that selector; NULL otherwise.
Method HKTMethod(Class cls, Protocol *shape, SEL selector, BOOL isInstanceMethod);

/// Overrides that method on `cls` itself, storing the implementation it replaces in `original`
/// before the override takes effect. Changes nothing when HKTMethod finds none.
void HKTReplace(Class cls, Protocol *shape, SEL selector, BOOL isInstanceMethod, IMP replacement, IMP *original);

/// Adds the HackerTube section to the app's Settings. NO when this YouTube version lacks a member it needs.
BOOL HKTInstallSettings(void);

/// Whether this YouTube version has every member the Home replacement needs.
BOOL HKTHomeSupported(void);

/// Replaces the Home feed with the web view. Hooks nothing unless HKTHomeSupported.
void HKTInstallHome(void);
