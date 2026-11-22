#import "HackerTube.h"

@protocol HKTPlayerPiPController
- (BOOL)canEnablePictureInPicture;
@end

@interface NSObject (HKTPlaybackOwner)
- (id)parentResponder;
- (id)playerViewControllerTraits;
@end

NSString *const HKTAllowShortsPiPKey = @"HackerTubeAllowShortsPiP";
static Ivar PlaybackDelegate;
static IMP OriginalCanEnable;

static BOOL CanEnable(id self, SEL cmd) {
    if (!((BOOL (*)(id, SEL))OriginalCanEnable)(self, cmd)) return NO;
    id playback = object_getIvar(self, PlaybackDelegate);
    id player = [playback respondsToSelector:@selector(parentResponder)] ? [playback parentResponder] : nil;
    id traits = [player respondsToSelector:@selector(playerViewControllerTraits)] ? [player playerViewControllerTraits] : nil;
    // YTReelPlayerProviderImpl assigns this name to the player, not to the video it plays.
    if ([traits respondsToSelector:@selector(name)] && [@"com.google.youtube.reel.watch" isEqual:[traits name]]) {
        return [NSUserDefaults.standardUserDefaults boolForKey:HKTAllowShortsPiPKey];
    }
    return YES;
}

void HKTInstallShortsPiP(void) {
    Class cls = NSClassFromString(@"YTPlayerPIPController");
    PlaybackDelegate = class_getInstanceVariable(cls, "_delegate");
    if (!PlaybackDelegate || ivar_getTypeEncoding(PlaybackDelegate)[0] != '@') return;
    HKTReplace(cls, @protocol(HKTPlayerPiPController), @selector(canEnablePictureInPicture), YES,
               (IMP)CanEnable, &OriginalCanEnable);
}
