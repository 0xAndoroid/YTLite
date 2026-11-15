#import "HackerTube.h"

NSString *const HKTHomeEnabledKey = @"HackerTubeHomeEnabled";

Method HKTMethod(Class cls, Protocol *shape, SEL selector, BOOL isInstanceMethod) {
    Method method = isInstanceMethod ? class_getInstanceMethod(cls, selector) : class_getClassMethod(cls, selector);
    const char *types = protocol_getMethodDescription(shape, selector, YES, isInstanceMethod).types;
    return method && types && strcmp(method_getTypeEncoding(method), types) == 0 ? method : NULL;
}

BOOL HKTReplace(Class cls, Protocol *shape, SEL selector, BOOL isInstanceMethod, IMP replacement, IMP *original) {
    Method method = HKTMethod(cls, shape, selector, isInstanceMethod);
    if (!method) return NO;
    *original = method_getImplementation(method);
    Class owner = isInstanceMethod ? cls : object_getClass(cls);
    // An inherited method gets an override on this class; its superclass and siblings keep theirs.
    if (!class_addMethod(owner, selector, replacement, method_getTypeEncoding(method))) {
        method_setImplementation(method, replacement);
    }
    return YES;
}

__attribute__((constructor)) static void Start(void) {
    // Home is replaced only while the switch that turns it off again is reachable.
    if (HKTInstallSettings() && [NSUserDefaults.standardUserDefaults boolForKey:HKTHomeEnabledKey]) HKTInstallHome();
}
