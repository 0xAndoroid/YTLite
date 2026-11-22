#import "HackerTube.h"

@protocol HKTPlayerPiPController
- (BOOL)canEnablePictureInPicture;
@end

@protocol HKTLocalPlaybackController
- (BOOL)isPlaybackBackgroundable;
- (void)appDidEnterBackground;
- (BOOL)isActivePlayback;
- (void)updateLockScreenController;
@end

@interface NSObject (HKTPlaybackOwner)
- (id)parentResponder;
- (id)playerViewControllerTraits;
@end

NSString *const HKTAllowShortsBackgroundPlaybackKey = @"HackerTubeAllowShortsPiP";
static Ivar PlaybackDelegate;
static IMP OriginalCanEnable, OriginalBackgroundable, OriginalEnterBackground;

static BOOL AllowsBackgroundPlayback(id playback) {
    id player = [playback respondsToSelector:@selector(parentResponder)] ? [playback parentResponder] : nil;
    id traits = [player respondsToSelector:@selector(playerViewControllerTraits)] ? [player playerViewControllerTraits] : nil;
    // YTReelPlayerProviderImpl assigns this name to the player, not to the video it plays.
    if ([traits respondsToSelector:@selector(name)] && [@"com.google.youtube.reel.watch" isEqual:[traits name]]) {
        return [NSUserDefaults.standardUserDefaults boolForKey:HKTAllowShortsBackgroundPlaybackKey];
    }
    return YES;
}

static BOOL CanEnable(id self, SEL cmd) {
    return ((BOOL (*)(id, SEL))OriginalCanEnable)(self, cmd)
        && AllowsBackgroundPlayback(object_getIvar(self, PlaybackDelegate));
}

static BOOL IsPlaybackBackgroundable(id self, SEL cmd) {
    return ((BOOL (*)(id, SEL))OriginalBackgroundable)(self, cmd) && AllowsBackgroundPlayback(self);
}

static void DidEnterBackground(id<HKTLocalPlaybackController> self, SEL cmd) {
    ((void (*)(id, SEL))OriginalEnterBackground)(self, cmd);
    // An already paused Short may not emit the media-state change that normally refreshes Now Playing.
    if ([self isActivePlayback] && !AllowsBackgroundPlayback(self)) [self updateLockScreenController];
}

void HKTInstallShortsPlaybackPolicy(void) {
    Class local = NSClassFromString(@"YTLocalPlaybackController");
    Protocol *shape = @protocol(HKTLocalPlaybackController);
    HKTReplace(local, shape, @selector(isPlaybackBackgroundable), YES, (IMP)IsPlaybackBackgroundable, &OriginalBackgroundable);
    if (OriginalBackgroundable && HKTMethod(local, shape, @selector(isActivePlayback), YES)
        && HKTMethod(local, shape, @selector(updateLockScreenController), YES)) {
        HKTReplace(local, shape, @selector(appDidEnterBackground), YES, (IMP)DidEnterBackground, &OriginalEnterBackground);
    }
    Class cls = NSClassFromString(@"YTPlayerPIPController");
    PlaybackDelegate = class_getInstanceVariable(cls, "_delegate");
    if (!PlaybackDelegate || ivar_getTypeEncoding(PlaybackDelegate)[0] != '@') return;
    HKTReplace(cls, @protocol(HKTPlayerPiPController), @selector(canEnablePictureInPicture), YES,
               (IMP)CanEnable, &OriginalCanEnable);
}
