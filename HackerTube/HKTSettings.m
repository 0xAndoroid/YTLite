#import "HackerTube.h"

// Shapes of the YouTube Settings members used here, read from the 21.44.4 executable; the same
// section mechanism the open-source YouPiP and YTVideoOverlay tweaks use. HKTInstallSettings
// compares each with the running app before anything is hooked or called.
@protocol HKTSettingsPresentationData
+ (NSArray<NSNumber *> *)settingsCategoryOrder;
@end

@protocol HKTSettingsGroupData
- (NSArray<NSNumber *> *)orderedCategories;
- (NSUInteger)type;
@end

@protocol HKTSettingsSectionItemManager
- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry;
@end

@protocol HKTSettingsDataDelegate
- (void)setSectionItems:(NSMutableArray *)items forCategory:(NSUInteger)category title:(NSString *)title icon:(id)icon titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden;
@end

@protocol HKTSettingsSectionItem
+ (id)switchItemWithTitle:(NSString *)title titleDescription:(NSString *)titleDescription accessibilityIdentifier:(NSString *)identifier switchOn:(BOOL)on switchBlock:(BOOL (^)(id cell, BOOL on))block settingItemId:(int)itemID;
@end

// Added to YTSettingsGroupData by the YouGroupSettings tweak when it is loaded: the mutable list
// of categories in its "Tweaks" group.
@protocol HKTYouGroupSettings
+ (NSMutableArray<NSNumber *> *)tweaks;
@end

// 'hktb'. YouTube's own categories are below 0x25; each tweak picks a constant of its own.
static const NSUInteger Section = 0x686B7462;
// The group of YouTube's own categories that tweaks join when YouGroupSettings is absent.
static const NSUInteger AccountGroup = 1;

static IMP OriginalOrder, OriginalCategories, OriginalUpdate;

static NSArray<NSNumber *> *Order(id self, SEL _cmd) {
    NSArray<NSNumber *> *order = ((NSArray *(*)(id, SEL))OriginalOrder)(self, _cmd);
    if (![order isKindOfClass:NSArray.class]) return order;
    NSUInteger anchor = [order indexOfObject:@1];
    NSMutableArray<NSNumber *> *result = [order mutableCopy];
    [result insertObject:@(Section) atIndex:anchor == NSNotFound ? order.count : anchor + 1];
    return result;
}

static NSArray<NSNumber *> *Categories(id self, SEL _cmd) {
    Class groups = [self class];
    if ([groups respondsToSelector:@selector(tweaks)]) {
        NSMutableArray<NSNumber *> *tweaks = [(Class<HKTYouGroupSettings>)groups tweaks];
        // The Tweaks group returns this same array from the original getter below.
        if ([tweaks isKindOfClass:NSMutableArray.class] && ![tweaks containsObject:@(Section)]) [tweaks addObject:@(Section)];
        return ((NSArray *(*)(id, SEL))OriginalCategories)(self, _cmd);
    }
    NSArray<NSNumber *> *categories = ((NSArray *(*)(id, SEL))OriginalCategories)(self, _cmd);
    if ([(id<HKTSettingsGroupData>)self type] != AccountGroup || ![categories isKindOfClass:NSArray.class]) return categories;
    return [@[@(Section)] arrayByAddingObjectsFromArray:categories];
}

static void Update(id self, SEL _cmd, NSUInteger category, id entry) {
    if (category != Section) {
        ((void (*)(id, SEL, NSUInteger, id))OriginalUpdate)(self, _cmd, category, entry);
        return;
    }
    id<HKTSettingsDataDelegate> delegate = object_getIvar(self, class_getInstanceVariable([self class], "_dataDelegate"));
    if (![(id)delegate respondsToSelector:@selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:)]) return;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *description = HKTHomeSupported()
        ? @"Shows hackertube.org in place of the Home feed. Videos open in the YouTube player. Restart YouTube to apply."
        : @"Not available in this version of YouTube.";
    Class<HKTSettingsSectionItem> items = NSClassFromString(@"YTSettingsSectionItem");
    id toggle = [items switchItemWithTitle:@"HackerTube Home" titleDescription:description
        accessibilityIdentifier:@"hackertube.home" switchOn:[defaults boolForKey:HKTHomeEnabledKey]
        switchBlock:^BOOL(id cell, BOOL on) {
            [defaults setBool:on forKey:HKTHomeEnabledKey];
            return YES;
        } settingItemId:0];
    if (!toggle) return;
    [delegate setSectionItems:[NSMutableArray arrayWithObject:toggle] forCategory:Section title:@"HackerTube"
        icon:nil titleDescription:nil headerHidden:NO];
}

BOOL HKTInstallSettings(void) {
    Class presentation = NSClassFromString(@"YTAppSettingsPresentationData");
    Class groups = NSClassFromString(@"YTSettingsGroupData");
    Class manager = NSClassFromString(@"YTSettingsSectionItemManager");
    SEL order = @selector(settingsCategoryOrder), categories = @selector(orderedCategories);
    SEL update = @selector(updateSectionForCategory:withEntry:);
    SEL setItems = @selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:);

    Ivar delegate = class_getInstanceVariable(manager, "_dataDelegate");
    Protocol *appDelegate = NSProtocolFromString(@"YTAppSettingsSectionItemDataDelegate");
    const char *appSetItems = appDelegate ? protocol_getMethodDescription(appDelegate, setItems, YES, YES).types : NULL;
    const char *setItemsShape = protocol_getMethodDescription(@protocol(HKTSettingsDataDelegate), setItems, YES, YES).types;
    if (!delegate || ivar_getTypeEncoding(delegate)[0] != '@' || !appSetItems || strcmp(appSetItems, setItemsShape) != 0
        || !HKTMethod(NSClassFromString(@"YTSettingsSectionItem"), @protocol(HKTSettingsSectionItem),
                      @selector(switchItemWithTitle:titleDescription:accessibilityIdentifier:switchOn:switchBlock:settingItemId:), NO)
        || !HKTMethod(groups, @protocol(HKTSettingsGroupData), @selector(type), YES)
        || !HKTMethod(presentation, @protocol(HKTSettingsPresentationData), order, NO)
        || !HKTMethod(groups, @protocol(HKTSettingsGroupData), categories, YES)
        || !HKTMethod(manager, @protocol(HKTSettingsSectionItemManager), update, YES)) return NO;

    HKTReplace(presentation, @protocol(HKTSettingsPresentationData), order, NO, (IMP)Order, &OriginalOrder);
    HKTReplace(groups, @protocol(HKTSettingsGroupData), categories, YES, (IMP)Categories, &OriginalCategories);
    HKTReplace(manager, @protocol(HKTSettingsSectionItemManager), update, YES, (IMP)Update, &OriginalUpdate);
    return YES;
}
