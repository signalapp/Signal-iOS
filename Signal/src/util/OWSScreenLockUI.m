//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSScreenLockUI.h"
#import "OWSWindowManager.h"
#import "Signal-Swift.h"
#import <SignalMessaging/ScreenLockViewController.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSScreenLockUI () <ScreenLockViewDelegate>

@property (nonatomic) UIWindow *screenBlockingWindow;
@property (nonatomic) ScreenLockViewController *screenBlockingViewController;

// Unlike UIApplication.applicationState, this state reflects the
// notifications, i.e. "did become active", "will resign active",
// "will enter foreground", "did enter background".
//
// We want to update our state to reflect these transitions and have
// the "update" logic be consistent with "last reported" state. i.e.
// when you're responding to "will resign active", we need to behave
// as though we're already inactive.
//
// Secondly, we need to show the screen protection _before_ we become
// inactive in order for it to be reflected in the app switcher.
@property (nonatomic) BOOL appIsInactiveOrBackground;
@property (nonatomic) BOOL appIsInBackground;

@property (nonatomic) BOOL isShowingScreenLockUI;

@property (nonatomic) BOOL didLastUnlockAttemptFail;

// We want to remain in "screen lock" mode while "local auth"
// UI is dismissing. So we lazily clear isShowingScreenLockUI
// using this property.
@property (nonatomic) BOOL shouldClearAuthUIWhenActive;

// Indicates whether or not the user is currently locked out of
// the app.  Should only be set if OWSScreenLock.isScreenLockEnabled.
//
// * The user is locked out by default on app launch.
// * The user is also locked out if they spend more than
//   "timeout" seconds outside the app.  When the user leaves
//   the app, a "countdown" begins.
@property (nonatomic) BOOL isScreenLockLocked;

// The "countdown" until screen lock takes effect.
@property (nonatomic, nullable) NSDate *screenLockCountdownDate;

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

    OWSAssertIsOnMainThread();

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
                                             selector:@selector(screenLockDidChange:)
                                                 name:OWSScreenLock.ScreenLockDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(clockDidChange:)
                                                 name:NSSystemClockDidChangeNotification
                                               object:nil];
}

- (void)setupWithRootWindow:(UIWindow *)rootWindow
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(rootWindow);

    [self createScreenBlockingWindowWithRootWindow:rootWindow];
    OWSAssertDebug(self.screenBlockingWindow);
}

- (void)startObserving
{
    _appIsInactiveOrBackground = [UIApplication sharedApplication].applicationState != UIApplicationStateActive;

    [self observeNotifications];

    // Hide the screen blocking window until "app is ready" to
    // avoid blocking the loading view.
    [self updateScreenBlockingWindow:ScreenLockUIStateNone animated:NO];

    // Initialize the screen lock state.
    //
    // It's not safe to access OWSScreenLock.isScreenLockEnabled
    // until the app is ready.
    [AppReadiness runNowOrWhenAppIsReady:^{
        self.isScreenLockLocked = OWSScreenLock.sharedManager.isScreenLockEnabled;
        
        [self ensureUI];
    }];
}

#pragma mark - Methods

- (void)tryToActivateScreenLockBasedOnCountdown
{
    OWSAssertDebug(!self.appIsInBackground);
    OWSAssertIsOnMainThread();

    if (!AppReadiness.isAppReady) {
        // It's not safe to access OWSScreenLock.isScreenLockEnabled
        // until the app is ready.
        //
        // We don't need to try to lock the screen lock;
        // It will be initialized by `setupWithRootWindow`.
        OWSLogVerbose(@"tryToActivateScreenLockUponBecomingActive NO 0");
        return;
    }
    if (!OWSScreenLock.sharedManager.isScreenLockEnabled) {
        // Screen lock is not enabled.
        OWSLogVerbose(@"tryToActivateScreenLockUponBecomingActive NO 1");
        return;
    }
    if (self.isScreenLockLocked) {
        // Screen lock is already activated.
        OWSLogVerbose(@"tryToActivateScreenLockUponBecomingActive NO 2");
        return;
    }
    if (!self.screenLockCountdownDate) {
        // We became inactive, but never started a countdown.
        OWSLogVerbose(@"tryToActivateScreenLockUponBecomingActive NO 3");
        return;
    }
    NSTimeInterval countdownInterval = fabs([self.screenLockCountdownDate timeIntervalSinceNow]);
    OWSAssertDebug(countdownInterval >= 0);
    NSTimeInterval screenLockTimeout = OWSScreenLock.sharedManager.screenLockTimeout;
    OWSAssertDebug(screenLockTimeout >= 0);
    if (countdownInterval >= screenLockTimeout) {
        self.isScreenLockLocked = YES;

        OWSLogVerbose(
            @"tryToActivateScreenLockUponBecomingActive YES 4 (%0.3f >= %0.3f)", countdownInterval, screenLockTimeout);
    } else {
        OWSLogVerbose(
            @"tryToActivateScreenLockUponBecomingActive NO 5 (%0.3f < %0.3f)", countdownInterval, screenLockTimeout);
    }
}

// Setter for property indicating that the app is either
// inactive or in the background, e.g. not "foreground and active."
- (void)setAppIsInactiveOrBackground:(BOOL)appIsInactiveOrBackground
{
    OWSAssertIsOnMainThread();

    _appIsInactiveOrBackground = appIsInactiveOrBackground;

    if (appIsInactiveOrBackground) {
        if (!self.isShowingScreenLockUI) {
            [self startScreenLockCountdownIfNecessary];
        }
    } else {
        [self tryToActivateScreenLockBasedOnCountdown];

        OWSLogInfo(@"setAppIsInactiveOrBackground clear screenLockCountdownDate.");
        self.screenLockCountdownDate = nil;
    }

    [self ensureUI];
}

// Setter for property indicating that the app is in the background.
// If true, by definition the app is not active.
- (void)setAppIsInBackground:(BOOL)appIsInBackground
{
    OWSAssertIsOnMainThread();

    _appIsInBackground = appIsInBackground;

    if (self.appIsInBackground) {
        [self startScreenLockCountdownIfNecessary];
    } else {
        [self tryToActivateScreenLockBasedOnCountdown];
    }

    [self ensureUI];
}

- (void)startScreenLockCountdownIfNecessary
{
    OWSLogVerbose(@"startScreenLockCountdownIfNecessary: %d", self.screenLockCountdownDate != nil);

    if (!self.screenLockCountdownDate) {
        OWSLogInfo(@"startScreenLockCountdown.");
        self.screenLockCountdownDate = [NSDate new];
    }

    self.didLastUnlockAttemptFail = NO;
}

// Ensure that:
//
// * The blocking window has the correct state.
// * That we show the "iOS auth UI to unlock" if necessary.
- (void)ensureUI
{
    OWSAssertIsOnMainThread();

    if (!AppReadiness.isAppReady) {
        [AppReadiness runNowOrWhenAppIsReady:^{
            [self ensureUI];
        }];
        return;
    }

    ScreenLockUIState desiredUIState = self.desiredUIState;

    OWSLogVerbose(@"ensureUI: %@", NSStringForScreenLockUIState(desiredUIState));

    [self updateScreenBlockingWindow:desiredUIState animated:YES];

    // Show the "iOS auth UI to unlock" if necessary.
    if (desiredUIState == ScreenLockUIStateScreenLock && !self.didLastUnlockAttemptFail) {
        [self tryToPresentAuthUIToUnlockScreenLock];
    }
}

- (void)tryToPresentAuthUIToUnlockScreenLock
{
    OWSAssertIsOnMainThread();

    if (self.isShowingScreenLockUI) {
        // We're already showing the auth UI; abort.
        return;
    }
    if (self.appIsInactiveOrBackground) {
        // Never show the auth UI unless active.
        return;
    }

    OWSLogInfo(@"try to unlock screen lock");

    self.isShowingScreenLockUI = YES;

    [OWSScreenLock.sharedManager
        tryToUnlockScreenLockWithSuccess:^{
            OWSLogInfo(@"unlock screen lock succeeded.");

            self.isShowingScreenLockUI = NO;

            self.isScreenLockLocked = NO;

            [self ensureUI];
        }
        failure:^(NSError *error) {
            OWSLogInfo(@"unlock screen lock failed.");

            [self clearAuthUIWhenActive];

            self.didLastUnlockAttemptFail = YES;

            [self showScreenLockFailureAlertWithMessage:error.localizedDescription];
        }
        unexpectedFailure:^(NSError *error) {
            OWSLogInfo(@"unlock screen lock unexpectedly failed.");

            // Local Authentication isn't working properly.
            // This isn't covered by the docs or the forums but in practice
            // it appears to be effective to retry again after waiting a bit.
            dispatch_async(dispatch_get_main_queue(), ^{
                [self clearAuthUIWhenActive];
            });
        }
        cancel:^{
            OWSLogInfo(@"unlock screen lock cancelled.");

            [self clearAuthUIWhenActive];

            self.didLastUnlockAttemptFail = YES;

            // Re-show the unlock UI.
            [self ensureUI];
        }];

    [self ensureUI];
}

// Determines what the state of the app should be.
- (ScreenLockUIState)desiredUIState
{
    if (self.isScreenLockLocked) {
        if (self.appIsInactiveOrBackground) {
            OWSLogVerbose(@"desiredUIState: screen protection 1.");
            return ScreenLockUIStateScreenProtection;
        } else {
            OWSLogVerbose(@"desiredUIState: screen lock 2.");
            return ScreenLockUIStateScreenLock;
        }
    }

    if (!self.appIsInactiveOrBackground) {
        // App is inactive or background.
        OWSLogVerbose(@"desiredUIState: none 3.");
        return ScreenLockUIStateNone;
    }

    if (Environment.shared.preferences.screenSecurityIsEnabled) {
        OWSLogVerbose(@"desiredUIState: screen protection 4.");
        return ScreenLockUIStateScreenProtection;
    } else {
        OWSLogVerbose(@"desiredUIState: none 5.");
        return ScreenLockUIStateNone;
    }
}

- (void)showScreenLockFailureAlertWithMessage:(NSString *)message
{
    OWSAssertIsOnMainThread();

    [OWSAlerts showAlertWithTitle:NSLocalizedString(@"SCREEN_LOCK_UNLOCK_FAILED",
                                      @"Title for alert indicating that screen lock could not be unlocked.")
                          message:message
                      buttonTitle:nil
                     buttonAction:^(UIAlertAction *action) {
                         // After the alert, update the UI.
                         [self ensureUI];
                     }
               fromViewController:self.screenBlockingWindow.rootViewController];
}

// 'Screen Blocking' window obscures the app screen:
//
// * In the app switcher.
// * During 'Screen Lock' unlock process.
- (void)createScreenBlockingWindowWithRootWindow:(UIWindow *)rootWindow
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(rootWindow);

    UIWindow *window = [[UIWindow alloc] initWithFrame:rootWindow.bounds];
    window.hidden = NO;
    window.windowLevel = UIWindowLevel_Background;
    window.opaque = YES;
    window.backgroundColor = UIColor.ows_materialBlueColor;

    ScreenLockViewController *viewController = [ScreenLockViewController new];
    viewController.delegate = self;
    window.rootViewController = viewController;

    self.screenBlockingWindow = window;
    self.screenBlockingViewController = viewController;
}

// The "screen blocking" window has three possible states:
//
// * "Just a logo".  Used when app is launching and in app switcher.  Must match the "Launch Screen"
//    storyboard pixel-for-pixel.
// * "Screen Lock, local auth UI presented". Move the Signal logo so that it is visible.
// * "Screen Lock, local auth UI not presented". Move the Signal logo so that it is visible,
//    show "unlock" button.
- (void)updateScreenBlockingWindow:(ScreenLockUIState)desiredUIState animated:(BOOL)animated
{
    OWSAssertIsOnMainThread();

    BOOL shouldShowBlockWindow = desiredUIState != ScreenLockUIStateNone;

    [OWSWindowManager.sharedManager setIsScreenBlockActive:shouldShowBlockWindow];

    [self.screenBlockingViewController updateUIWithState:desiredUIState
                                             isLogoAtTop:self.isShowingScreenLockUI
                                                animated:animated];
}

#pragma mark - Events

- (void)screenLockDidChange:(NSNotification *)notification
{
    [self ensureUI];
}

- (void)clearAuthUIWhenActive
{
    // For continuity, continue to present blocking screen in "screen lock" mode while
    // dismissing the "local auth UI".
    if (self.appIsInactiveOrBackground) {
        self.shouldClearAuthUIWhenActive = YES;
    } else {
        self.isShowingScreenLockUI = NO;
        [self ensureUI];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    if (self.shouldClearAuthUIWhenActive) {
        self.shouldClearAuthUIWhenActive = NO;
        self.isShowingScreenLockUI = NO;
    }

    self.appIsInactiveOrBackground = NO;
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    self.appIsInactiveOrBackground = YES;
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    self.appIsInBackground = NO;
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    self.appIsInBackground = YES;
}

// Whenever the device date/time is edited by the user,
// trigger screen lock immediately if enabled.
- (void)clockDidChange:(NSNotification *)notification
{
    OWSLogInfo(@"clock did change");

    if (!AppReadiness.isAppReady) {
        // It's not safe to access OWSScreenLock.isScreenLockEnabled
        // until the app is ready.
        //
        // We don't need to try to lock the screen lock;
        // It will be initialized by `setupWithRootWindow`.
        OWSLogVerbose(@"clockDidChange 0");
        return;
    }
    self.isScreenLockLocked = OWSScreenLock.sharedManager.isScreenLockEnabled;

    // NOTE: this notifications fires _before_ applicationDidBecomeActive,
    // which is desirable.  Don't assume that though; call ensureUI
    // just in case it's necessary.
    [self ensureUI];
}

#pragma mark - ScreenLockViewDelegate

- (void)unlockButtonWasTapped
{
    OWSAssertIsOnMainThread();

    if (self.appIsInactiveOrBackground) {
        // This button can be pressed while the app is inactive
        // for a brief window while the iOS auth UI is dismissing.
        return;
    }

    OWSLogInfo(@"unlockButtonWasTapped");

    self.didLastUnlockAttemptFail = NO;

    [self ensureUI];
}

@end

NS_ASSUME_NONNULL_END
