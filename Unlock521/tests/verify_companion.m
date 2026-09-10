#import <Foundation/Foundation.h>
#import <dlfcn.h>

static NSUserDefaults *defaults;

@interface YTLUserDefaults : NSObject
+ (NSUserDefaults *)standardUserDefaults;
@end

@implementation YTLUserDefaults
+ (NSUserDefaults *)standardUserDefaults { return defaults; }
@end

@interface YTPSettingsBuilder : NSObject
- (NSArray *)rootTable;
- (NSArray *)prefsTable;
- (NSArray *)thanksTable;
@end

@implementation YTPSettingsBuilder
- (NSArray *)rootTable { return @[@"Player", @"Feed", @"Shorts", @"SponsorBlock"]; }
- (NSArray *)prefsTable { return @[@"Import", @"Export", @"Reset"]; }
- (NSArray *)thanksTable { return @[@"Supporters"]; }
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSCAssert(argc == 2, @"Expected companion dylib path");
        NSString *suite = [@"com.andoroid.unlock-test." stringByAppendingString:NSUUID.UUID.UUIDString];
        defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        [defaults setBool:NO forKey:@"dontRemindAccess"];
        [defaults setBool:NO forKey:@"noAds"];
        NSDictionary *expectedPreferences = [defaults persistentDomainForName:suite];
        YTPSettingsBuilder *builder = [YTPSettingsBuilder new];
        NSArray *root = [builder rootTable];
        NSArray *prefs = [builder prefsTable];
        NSArray *thanks = [builder thanksTable];

        void *library = dlopen(argv[1], RTLD_NOW);
        NSCAssert(library, @"Companion failed to load: %s", dlerror());
        BOOL preservedTables = [[builder rootTable] isEqual:root]
            && [[builder prefsTable] isEqual:prefs]
            && [[builder thanksTable] isEqual:thanks];
        NSMutableDictionary *expected = [expectedPreferences mutableCopy];
        expected[@"dontRemindAccess"] = @YES;
        BOOL preservedPreferences = [[defaults persistentDomainForName:suite] isEqual:expected];
        [defaults removePersistentDomainForName:suite];
        NSCAssert(preservedTables, @"Feature settings and auxiliary pages must retain their original contents");
        NSCAssert(preservedPreferences, @"Suppress the reminder without changing saved feature preferences");
        puts("Companion: settings pages preserved; reminder suppressed; feature preferences unchanged");
    }
    return 0;
}
