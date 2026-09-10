#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

typedef id (*YTLiteUnlockObjectMessageSend)(id, SEL);

__attribute__((constructor))
static void YTLiteUnlockConstructor(void) {
    @autoreleasepool {
        NSUserDefaults *defaults = ((YTLiteUnlockObjectMessageSend)objc_msgSend)(
            objc_getClass("YTLUserDefaults"), sel_registerName("standardUserDefaults")
        );
        // The activation reminder reads this preference directly, outside the feature gates.
        if (![defaults boolForKey:@"dontRemindAccess"]) {
            [defaults setBool:YES forKey:@"dontRemindAccess"];
        }
    }
}
