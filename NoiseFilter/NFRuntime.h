#import <Foundation/Foundation.h>
#import <objc/runtime.h>

BOOL NFMethodMatches(Class cls, SEL selector, const char *types);
IMP NFHook(Class cls, SEL selector, const char *types, IMP replacement);
