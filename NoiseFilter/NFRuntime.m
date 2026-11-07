#import "NFRuntime.h"

BOOL NFMethodMatches(Class cls, SEL selector, const char *types) {
    Method method = class_getInstanceMethod(cls, selector);
    return method && strcmp(method_getTypeEncoding(method), types) == 0;
}
IMP NFHook(Class cls, SEL selector, const char *types, IMP replacement) {
    if (!NFMethodMatches(cls, selector, types)) return NULL;
    Method method = class_getInstanceMethod(cls, selector);
    IMP original = method_getImplementation(method);
    // An inherited method must be overridden here, never replaced on its shared superclass.
    if (!class_addMethod(cls, selector, replacement, types)) method_setImplementation(method, replacement);
    return original;
}
