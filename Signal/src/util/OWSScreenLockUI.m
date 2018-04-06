//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSScreenLockUI.h"
#import "Signal-Swift.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSScreenLockUI ()

@property (nonatomic) UIWindow *screenBlockingWindow;
@property (nonatomic) UIViewController *screenBlockingViewController;
@property (nonatomic) UIView *screenBlockingImageView;
@property (nonatomic) UIView *screenBlockingButton;
@property (nonatomic) NSArray<NSLayoutConstraint *> *screenBlockingConstraints;
@property (nonatomic) NSString *screenBlockingSignature;

// Unlike UIApplication.applicationState, this state is
// updated conservatively, e.g. the flag is cleared during
// "will enter background."
@property (nonatomic) BOOL appIsInactive;
@property (nonatomic) BOOL appIsInBackground;

@property (nonatomic) BOOL isShowingScreenLockUI;
@property (nonatomic) BOOL didLastUnlockAttemptFail;

// We want to remain in "screen lock" mode while "local auth"
// UI is dismissing.
@property (nonatomic) BOOL shouldClearAuthUIWhenActive;

// Indicates whether or not the user is currently locked out of
// the app.  Only applies if OWSScreenLock.isScreenLockEnabled.
//
// * The user is locked out out by default on app launch.
// * The user is also locked out if they spend more than
//   "timeout" seconds outside the app.  When the user leaves
//   the app, a "countdown" begins.
@property (nonatomic) BOOL isScreenLockUnlocked;

@property (nonatomic, nullable) NSDate *screenLockCountdownDate;

// We normally start the "countdown" when the app enters the background,
// But we also want to start the "countdown" if the app is inactive for
// more than N seconds.
@property (nonatomic, nullable) NSTimer *inactiveTimer;


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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenLockWasEnabled:)
                                                 name:OWSScreenLock.ScreenLockWasEnabled
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

- (void)tryToActivateScreenLockUponBecomingActive
{
    OWSAssert(!self.appIsInactive);

    if (!self.isScreenLockUnlocked) {
        // Screen lock is already activated.
        DDLogVerbose(@"%@ tryToActivateScreenLockUponBecomingActive NO 0", self.logTag);
        return;
    }
    if (!self.screenLockCountdownDate) {
        // We became inactive, but never started a countdown.
        DDLogVerbose(@"%@ tryToActivateScreenLockUponBecomingActive NO 1", self.logTag);
        return;
    }
    NSTimeInterval countdownInterval = fabs([self.screenLockCountdownDate timeIntervalSinceNow]);
    OWSAssert(countdownInterval >= 0);
    NSTimeInterval screenLockTimeout = OWSScreenLock.sharedManager.screenLockTimeout;
    OWSAssert(screenLockTimeout >= 0);
    if (countdownInterval >= screenLockTimeout) {
        self.isScreenLockUnlocked = NO;
        DDLogVerbose(@"%@ tryToActivateScreenLockUponBecomingActive YES 1 (%0.3f >= %0.3f)",
            self.logTag,
            countdownInterval,
            screenLockTimeout);
    } else {
        DDLogVerbose(@"%@ tryToActivateScreenLockUponBecomingActive NO 2 (%0.3f < %0.3f)",
            self.logTag,
            countdownInterval,
            screenLockTimeout);
    }
}

- (void)setAppIsInactive:(BOOL)appIsInactive
{
    _appIsInactive = appIsInactive;

    if (!appIsInactive) {
        [self tryToActivateScreenLockUponBecomingActive];

        self.screenLockCountdownDate = nil;
    }

    [self startInactiveTimerIfNecessary];

    [self ensureScreenProtection];
}

- (void)setAppIsInBackground:(BOOL)appIsInBackground
{
    if (appIsInBackground && !_appIsInBackground) {
        [self startScreenLockCountdownIfNecessary];
    }

    _appIsInBackground = appIsInBackground;

    [self ensureScreenProtection];
}

- (void)startScreenLockCountdownIfNecessary
{
    if (!self.screenLockCountdownDate) {
        DDLogVerbose(@"%@ startScreenLockCountdownIfNecessary.", self.logTag);
        self.screenLockCountdownDate = [NSDate new];
    }

    self.didLastUnlockAttemptFail = NO;

    [self clearInactiveTimer];
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
    [self updateScreenBlockingWindow:shouldShowBlockWindow shouldHaveScreenLock:shouldHaveScreenLock animated:YES];

    if (shouldHaveScreenLock && !self.didLastUnlockAttemptFail) {
        [self tryToPresentScreenLockUI];
    }
}

- (void)tryToPresentScreenLockUI
{
    OWSAssertIsOnMainThread();

    // If we no longer want to present the screen lock UI, abort.
    if (!self.shouldHaveScreenLock) {
        return;
    }
    if (self.didLastUnlockAttemptFail) {
        return;
    }
    if (self.isShowingScreenLockUI) {
        return;
    }

    DDLogInfo(@"%@, try to unlock screen lock", self.logTag);

    self.isShowingScreenLockUI = YES;

    [OWSScreenLock.sharedManager tryToUnlockScreenLockWithSuccess:^{
        DDLogInfo(@"%@ unlock screen lock succeeded.", self.logTag);

        self.isShowingScreenLockUI = NO;

        self.isScreenLockUnlocked = YES;

        [self ensureScreenProtection];
    }
        failure:^(NSError *error) {
            DDLogInfo(@"%@ unlock screen lock failed.", self.logTag);

            [self clearAuthUIWhenActive];

            self.didLastUnlockAttemptFail = YES;

            [self showScreenLockFailureAlertWithMessage:error.localizedDescription];
        }
        unexpectedFailure:^(NSError *error) {
            DDLogInfo(@"%@ unlock screen lock unexpectedly failed.", self.logTag);

            // Local Authentication isn't working properly.
            // This isn't covered by the docs or the forums but in practice
            // it appears to be effective to retry again after waiting a bit.
            dispatch_async(dispatch_get_main_queue(), ^{
                [self clearAuthUIWhenActive];
            });
        }
        cancel:^{
            DDLogInfo(@"%@ unlock screen lock cancelled.", self.logTag);

            [self clearAuthUIWhenActive];

            self.didLastUnlockAttemptFail = YES;

            // Re-show the unlock UI.
            [self ensureScreenProtection];
        }];

    [self ensureScreenProtection];
}

- (BOOL)shouldHaveScreenProtection
{
    // Show 'Screen Protection' if:
    //
    // * App is inactive and...
    // * 'Screen Protection' is enabled.
    if (!self.appIsInactive) {
        return NO;
    } else if (!Environment.preferences.screenSecurityIsEnabled) {
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)shouldHaveScreenLock
{
    if (![TSAccountManager isRegistered]) {
        // Don't show 'Screen Lock' if user is not registered.
        DDLogVerbose(@"%@ shouldHaveScreenLock NO 1.", self.logTag);
        return NO;
    } else if (!OWSScreenLock.sharedManager.isScreenLockEnabled) {
        // Don't show 'Screen Lock' if 'Screen Lock' isn't enabled.
        DDLogVerbose(@"%@ shouldHaveScreenLock NO 2.", self.logTag);
        return NO;
    } else if (self.appIsInBackground) {
        // Don't show 'Screen Lock' if app is in background.
        DDLogVerbose(@"%@ shouldHaveScreenLock NO 4.", self.logTag);
        return NO;
    } else if (self.isShowingScreenLockUI) {
        // Maintain blocking window in 'screen lock' mode while we're
        // showing the 'Unlock Screen Lock' UI.
        DDLogVerbose(@"%@ shouldHaveScreenLock YES 0.", self.logTag);
        return YES;
    } else if (self.appIsInactive) {
        // Don't show 'Screen Lock' if app is inactive.
        DDLogVerbose(@"%@ shouldHaveScreenLock NO 5.", self.logTag);
        return NO;
    } else {
        BOOL shouldHaveScreenLock = !self.isScreenLockUnlocked;
        DDLogVerbose(@"%@ shouldHaveScreenLock ? %d.", self.logTag, shouldHaveScreenLock);
        return shouldHaveScreenLock;
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
    window.windowLevel = CGFLOAT_MAX;
    window.backgroundColor = UIColor.ows_materialBlueColor;

    UIViewController *viewController = [UIViewController new];
    viewController.view.backgroundColor = UIColor.ows_materialBlueColor;


    UIView *rootView = viewController.view;

    UIView *edgesView = [UIView containerView];
    [rootView addSubview:edgesView];
    [edgesView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [edgesView autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [edgesView autoPinWidthToSuperview];

    UIImage *image = [UIImage imageNamed:@"logoSignal"];
    UIImageView *imageView = [UIImageView new];
    imageView.image = image;
    [edgesView addSubview:imageView];
    [imageView autoHCenterInSuperview];

    const CGSize screenSize = UIScreen.mainScreen.bounds.size;
    const CGFloat shortScreenDimension = MIN(screenSize.width, screenSize.height);
    const CGFloat imageSize = round(shortScreenDimension / 3.f);
    [imageView autoSetDimension:ALDimensionWidth toSize:imageSize];
    [imageView autoSetDimension:ALDimensionHeight toSize:imageSize];

    const CGFloat kButtonHeight = 40.f;
    OWSFlatButton *button =
        [OWSFlatButton buttonWithTitle:NSLocalizedString(@"SCREEN_LOCK_UNLOCK_SIGNAL",
                                           @"Label for button on lock screen that lets users unlock Signal.")
                                  font:[OWSFlatButton fontForHeight:kButtonHeight]
                            titleColor:[UIColor ows_materialBlueColor]
                       backgroundColor:[UIColor whiteColor]
                                target:self
                              selector:@selector(showUnlockUI)];
    [edgesView addSubview:button];

    [button autoSetDimension:ALDimensionHeight toSize:kButtonHeight];
    [button autoPinLeadingToSuperviewWithMargin:50.f];
    [button autoPinTrailingToSuperviewWithMargin:50.f];
    const CGFloat kVMargin = 65.f;
    [button autoPinBottomToSuperviewWithMargin:kVMargin];

    window.rootViewController = viewController;

    self.screenBlockingWindow = window;
    self.screenBlockingViewController = viewController;
    self.screenBlockingImageView = imageView;
    self.screenBlockingButton = button;

    [self updateScreenBlockingWindow:YES shouldHaveScreenLock:NO animated:NO];
}

// The "screen blocking" window has three possible states:
//
// * "Just a logo".  Used when app is launching and in app switcher.  Must match the "Launch Screen"
//    storyboard pixel-for-pixel.
// * "Screen Lock, local auth UI presented". Move the Signal logo so that it is visible.
// * "Screen Lock, local auth UI not presented". Move the Signal logo so that it is visible,
//    show "unlock" button.
- (void)updateScreenBlockingWindow:(BOOL)shouldShowBlockWindow
              shouldHaveScreenLock:(BOOL)shouldHaveScreenLock
                          animated:(BOOL)animated
{
    OWSAssertIsOnMainThread();

    self.screenBlockingWindow.hidden = !shouldShowBlockWindow;

    UIView *rootView = self.screenBlockingViewController.view;

    [NSLayoutConstraint deactivateConstraints:self.screenBlockingConstraints];

    NSMutableArray<NSLayoutConstraint *> *screenBlockingConstraints = [NSMutableArray new];

    BOOL shouldShowUnlockButton = (!self.appIsInactive && !self.appIsInBackground && self.didLastUnlockAttemptFail);

    DDLogVerbose(@"%@ updateScreenBlockingWindow. shouldShowBlockWindow: %d, shouldHaveScreenLock: %d, "
                 @"shouldShowUnlockButton: %d.",
        self.logTag,
        shouldShowBlockWindow,
        shouldHaveScreenLock,
        shouldShowUnlockButton);

    NSString *signature = [NSString stringWithFormat:@"%d %d", shouldHaveScreenLock, self.isShowingScreenLockUI];
    if ([NSObject isNullableObject:self.screenBlockingSignature equalTo:signature]) {
        // Skip redundant work to avoid interfering with ongoing animations.
        return;
    }

    self.screenBlockingButton.hidden = !shouldHaveScreenLock;

    if (self.isShowingScreenLockUI) {
        const CGFloat kVMargin = 60.f;
        [screenBlockingConstraints addObject:[self.screenBlockingImageView autoPinEdge:ALEdgeTop
                                                                                toEdge:ALEdgeTop
                                                                                ofView:rootView
                                                                            withOffset:kVMargin]];
    } else {
        [screenBlockingConstraints addObject:[self.screenBlockingImageView autoVCenterInSuperview]];
    }

    self.screenBlockingConstraints = screenBlockingConstraints;
    self.screenBlockingSignature = signature;

    if (animated) {
        [UIView animateWithDuration:0.35f
                         animations:^{
                             [rootView layoutIfNeeded];
                         }];
    } else {
        [rootView layoutIfNeeded];
    }
}

- (void)showUnlockUI
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"showUnlockUI");

    self.didLastUnlockAttemptFail = NO;

    [self ensureScreenProtection];
}

#pragma mark - Events

- (void)screenLockDidChange:(NSNotification *)notification
{
    [self ensureScreenProtection];
}

- (void)screenLockWasEnabled:(NSNotification *)notification
{
    // When we enable screen lock, consider that an unlock.
    self.isScreenLockUnlocked = YES;

    DDLogVerbose(@"%@ screenLockWasEnabled", self.logTag);

    [self ensureScreenProtection];
}

- (void)registrationStateDidChange
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"registrationStateDidChange");

    [self ensureScreenProtection];
}

- (void)clearAuthUIWhenActive
{
    // For continuity, continue to present blocking screen in "screen lock" mode while
    // dismissing the "local auth UI".
    if (self.appIsInactive) {
        self.shouldClearAuthUIWhenActive = YES;
    } else {
        self.isShowingScreenLockUI = NO;
        [self ensureScreenProtection];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    if (self.shouldClearAuthUIWhenActive) {
        self.shouldClearAuthUIWhenActive = NO;
        self.isShowingScreenLockUI = NO;
    }

    self.appIsInactive = NO;
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    self.appIsInactive = YES;
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    self.appIsInBackground = NO;
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    self.appIsInBackground = YES;
}

#pragma mark - Inactive Timer

- (void)inactiveTimerDidFire
{
    [self startScreenLockCountdownIfNecessary];
}

- (void)startInactiveTimerIfNecessary
{
    if (self.appIsInactive && !self.isShowingScreenLockUI && !self.inactiveTimer) {
        [self.inactiveTimer invalidate];
        self.inactiveTimer = [NSTimer weakScheduledTimerWithTimeInterval:45.f
                                                                  target:self
                                                                selector:@selector(inactiveTimerDidFire)
                                                                userInfo:nil
                                                                 repeats:NO];
    }
}

- (void)clearInactiveTimer
{
    [self.inactiveTimer invalidate];
    self.inactiveTimer = nil;
}

@end

NS_ASSUME_NONNULL_END
