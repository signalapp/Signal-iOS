//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSScreenLockUI.h"
#import "Signal-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSScreenLockUI ()

// Unlike UIApplication.applicationState, this state is
// updated conservatively, e.g. the flag is cleared during
// "will enter background."
@property (nonatomic) BOOL appIsInactive;
@property (nonatomic) BOOL appIsInBackground;
@property (nonatomic, nullable) NSDate *appEnteredBackgroundDate;
@property (nonatomic) UIWindow *screenBlockingWindow;
@property (nonatomic) BOOL hasUnlockedScreenLock;
@property (nonatomic) BOOL isShowingScreenLockUI;

@property (nonatomic, nullable) NSTimer *screenLockUITimer;
@property (nonatomic, nullable) NSDate *lastUnlockAttemptDate;
@property (nonatomic, nullable) NSDate *lastUnlockSuccessDate;

@end

#pragma mark -

@implementation OWSScreenLockUI

+ (instancetype)sharedManager
{
    static OWSScreenLockUI *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initDefault];
    });
    return instance;
}

- (instancetype)initDefault
{
    self = [super init];

    if (!self) {
        return self;
    }

    [self observeNotifications];

    OWSSingletonAssert();

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:OWSApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:OWSApplicationWillEnterForegroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:OWSApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStateDidChange)
                                                 name:RegistrationStateDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenLockDidChange:)
                                                 name:OWSScreenLock.ScreenLockDidChange
                                               object:nil];
}

- (void)setupWithRootWindow:(UIWindow *)rootWindow
{
    OWSAssertIsOnMainThread();
    OWSAssert(rootWindow);

    [self prepareScreenProtectionWithRootWindow:rootWindow];

    [AppReadiness runNowOrWhenAppIsReady:^{
        [self ensureScreenProtection];
    }];
}

#pragma mark - Methods

- (void)setAppIsInactive:(BOOL)appIsInactive
{
    _appIsInactive = appIsInactive;

    [self ensureScreenProtection];
}

- (void)setAppIsInBackground:(BOOL)appIsInBackground
{
    if (appIsInBackground) {
        if (!_appIsInBackground) {
            // Whenever app enters background, clear this state.
            self.hasUnlockedScreenLock = NO;

            // Record the time when app entered background.
            self.appEnteredBackgroundDate = [NSDate new];
        }
    }

    _appIsInBackground = appIsInBackground;

    [self ensureScreenProtection];
}

- (void)ensureScreenProtection
{
    OWSAssertIsOnMainThread();

    if (!AppReadiness.isAppReady) {
        [AppReadiness runNowOrWhenAppIsReady:^{
            [self ensureScreenProtection];
        }];
        return;
    }

    BOOL shouldHaveScreenLock = self.shouldHaveScreenLock;
    BOOL shouldHaveScreenProtection = self.shouldHaveScreenProtection;

    BOOL shouldShowBlockWindow = shouldHaveScreenProtection || shouldHaveScreenLock;
    DDLogVerbose(@"%@, shouldHaveScreenProtection: %d, shouldHaveScreenLock: %d, shouldShowBlockWindow: %d",
        self.logTag,
        shouldHaveScreenProtection,
        shouldHaveScreenLock,
        shouldShowBlockWindow);
    if (self.screenBlockingWindow.hidden != !shouldShowBlockWindow) {
        DDLogInfo(@"%@, %@.", self.logTag, shouldShowBlockWindow ? @"showing block window" : @"hiding block window");
    }
    self.screenBlockingWindow.hidden = !shouldShowBlockWindow;

    [self.screenLockUITimer invalidate];
    self.screenLockUITimer = nil;

    if (shouldHaveScreenLock) {
        // In pincode-only mode (e.g. device pincode is set
        // but Touch ID/Face ID are not configured), the pincode
        // unlock UI is fullscreen and the app becomes inactive.
        // Hitting the home button will cancel the authentication
        // UI but not send the app to the background.  Therefore,
        // to send the "locked" app to the background, you need
        // to tap the home button twice.
        //
        // Therefore, if our last unlock attempt failed or was
        // cancelled, wait a couple of second before re-presenting
        // the "unlock screen lock UI" so that users have a chance
        // to hit home button again.
        BOOL shouldDelayScreenLockUI = YES;
        if (!self.lastUnlockAttemptDate) {
            shouldDelayScreenLockUI = NO;
        } else if (self.lastUnlockAttemptDate && self.lastUnlockSuccessDate &&
            [self.lastUnlockSuccessDate isAfterDate:self.lastUnlockAttemptDate]) {
            shouldDelayScreenLockUI = NO;
        }

        if (shouldDelayScreenLockUI) {
            DDLogVerbose(@"%@, Delaying Screen Lock UI.", self.logTag);
            self.screenLockUITimer = [NSTimer weakScheduledTimerWithTimeInterval:1.25f
                                                                          target:self
                                                                        selector:@selector(tryToPresentScreenLockUI)
                                                                        userInfo:nil
                                                                         repeats:NO];
        } else {
            [self tryToPresentScreenLockUI];
        }
    }
}

- (void)tryToPresentScreenLockUI
{
    OWSAssertIsOnMainThread();

    [self.screenLockUITimer invalidate];
    self.screenLockUITimer = nil;

    // If we no longer want to present the screen lock UI, abort.
    if (!self.shouldHaveScreenLock) {
        return;
    }
    if (self.isShowingScreenLockUI) {
        return;
    }

    DDLogInfo(@"%@, try to unlock screen lock", self.logTag);

    self.isShowingScreenLockUI = YES;
    self.lastUnlockAttemptDate = [NSDate new];

    [OWSScreenLock.sharedManager tryToUnlockScreenLockWithSuccess:^{
        DDLogInfo(@"%@ unlock screen lock succeeded.", self.logTag);
        self.isShowingScreenLockUI = NO;
        self.hasUnlockedScreenLock = YES;
        self.lastUnlockSuccessDate = [NSDate new];
        [self ensureScreenProtection];
    }
        failure:^(NSError *error) {
            DDLogInfo(@"%@ unlock screen lock failed.", self.logTag);
            self.isShowingScreenLockUI = NO;

            [self showScreenLockFailureAlertWithMessage:error.localizedDescription];
        }
        unexpectedFailure:^(NSError *error) {
            DDLogInfo(@"%@ unlock screen lock unexpectedly failed.", self.logTag);
            self.isShowingScreenLockUI = NO;

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self ensureScreenProtection];
            });
        }
        cancel:^{
            DDLogInfo(@"%@ unlock screen lock cancelled.", self.logTag);
            self.isShowingScreenLockUI = NO;

            // Re-show the unlock UI.
            [self ensureScreenProtection];
        }];
}

- (BOOL)shouldHaveScreenProtection
{
    // Show 'Screen Protection' if:
    //
    // * App is inactive and...
    // * 'Screen Protection' is enabled.
    BOOL shouldHaveScreenProtection = (self.appIsInactive && Environment.preferences.screenSecurityIsEnabled);
    return shouldHaveScreenProtection;
}

- (BOOL)shouldHaveScreenLock
{
    BOOL shouldHaveScreenLock = NO;
    if (![TSAccountManager isRegistered]) {
        // Don't show 'Screen Lock' if user is not registered.
    } else if (!OWSScreenLock.sharedManager.isScreenLockEnabled) {
        // Don't show 'Screen Lock' if 'Screen Lock' isn't enabled.
    } else if (self.hasUnlockedScreenLock) {
        // Don't show 'Screen Lock' if 'Screen Lock' has been unlocked.
    } else if (self.appIsInBackground) {
        // Don't show 'Screen Lock' if app is in background.
    } else if (self.appIsInactive) {
        // Don't show 'Screen Lock' if app is inactive.
    } else if (!self.appEnteredBackgroundDate) {
        // Show 'Screen Lock' if app has just launched.
        shouldHaveScreenLock = YES;
    } else {
        OWSAssert(self.appEnteredBackgroundDate);

        NSTimeInterval screenLockInterval = fabs([self.appEnteredBackgroundDate timeIntervalSinceNow]);
        NSTimeInterval screenLockTimeout = OWSScreenLock.sharedManager.screenLockTimeout;
        OWSAssert(screenLockInterval >= 0);
        OWSAssert(screenLockTimeout >= 0);
        if (screenLockInterval < screenLockTimeout) {
            // Don't show 'Screen Lock' if 'Screen Lock' timeout hasn't elapsed.
            shouldHaveScreenLock = NO;
        } else {
            // Otherwise, show 'Screen Lock'.
            shouldHaveScreenLock = YES;
        }
    }
    return shouldHaveScreenLock;
}

- (void)showScreenLockFailureAlertWithMessage:(NSString *)message
{
    OWSAssertIsOnMainThread();

    [OWSAlerts showAlertWithTitle:NSLocalizedString(@"SCREEN_LOCK_UNLOCK_FAILED",
                                      @"Title for alert indicating that screen lock could not be unlocked.")
                          message:message
                      buttonTitle:nil
                     buttonAction:^(UIAlertAction *action) {
                         // After the alert, re-show the unlock UI.
                         [self ensureScreenProtection];
                     }];
}

// 'Screen Blocking' window obscures the app screen:
//
// * In the app switcher.
// * During 'Screen Lock' unlock process.
- (void)prepareScreenProtectionWithRootWindow:(UIWindow *)rootWindow
{
    OWSAssertIsOnMainThread();
    OWSAssert(rootWindow);

    UIWindow *window = [[UIWindow alloc] initWithFrame:rootWindow.bounds];
    window.hidden = YES;
    window.opaque = YES;
    window.userInteractionEnabled = NO;
    window.windowLevel = CGFLOAT_MAX;
    window.backgroundColor = UIColor.ows_materialBlueColor;
    window.rootViewController =
        [[UIStoryboard storyboardWithName:@"Launch Screen" bundle:nil] instantiateInitialViewController];

    self.screenBlockingWindow = window;
}

#pragma mark - Events

- (void)screenLockDidChange:(NSNotification *)notification
{
    [self ensureScreenProtection];
}

- (void)registrationStateDidChange
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"registrationStateDidChange");

    [self ensureScreenProtection];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    self.appIsInactive = NO;
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    self.appIsInactive = YES;
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    // Clear the "delay Screen Lock UI" state; we don't want any
    // delays when presenting the "unlock screen lock UI" after
    // returning from background.
    [self.screenLockUITimer invalidate];
    self.screenLockUITimer = nil;
    self.lastUnlockAttemptDate = nil;
    self.lastUnlockSuccessDate = nil;

    self.appIsInBackground = NO;
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    self.appIsInBackground = YES;
}

@end

NS_ASSUME_NONNULL_END
