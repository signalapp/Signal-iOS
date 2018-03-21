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
@property (nonatomic, nullable) NSDate *appBecameInactiveDate;
@property (nonatomic) UIWindow *screenBlockingWindow;
@property (nonatomic) BOOL hasUnlockedScreenLock;
@property (nonatomic) BOOL isShowingScreenLockUI;

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
    if (appIsInactive) {
        if (!_appIsInactive) {
            // Whenever app becomes inactive, clear this state.
            self.hasUnlockedScreenLock = NO;

            // Note the time when app became inactive.
            self.appBecameInactiveDate = [NSDate new];
        }
    }

    _appIsInactive = appIsInactive;

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

    // Don't show 'Screen Protection' if:
    //
    // * App is active or...
    // * 'Screen Protection' is not enabled.
    BOOL shouldHaveScreenProtection = (self.appIsInactive && Environment.preferences.screenSecurityIsEnabled);

    BOOL shouldHaveScreenLock = NO;
    if (self.appIsInactive) {
        // Don't show 'Screen Lock' if app is inactive.
    } else if (![TSAccountManager isRegistered]) {
        // Don't show 'Screen Lock' if user is not registered.
    } else if (!OWSScreenLock.sharedManager.isScreenLockEnabled) {
        // Don't show 'Screen Lock' if 'Screen Lock' isn't enabled.
    } else if (self.hasUnlockedScreenLock) {
        // Don't show 'Screen Lock' if 'Screen Lock' has been unlocked.
    } else if (!self.appBecameInactiveDate) {
        // Show 'Screen Lock' if app hasn't become inactive yet (just launched).
        shouldHaveScreenLock = YES;
    } else {
        OWSAssert(self.appBecameInactiveDate);

        NSTimeInterval screenLockInterval = fabs([self.appBecameInactiveDate timeIntervalSinceNow]);
        NSTimeInterval screenLockTimeout = OWSScreenLock.sharedManager.screenLockTimeout;
        OWSAssert(screenLockInterval >= 0);
        OWSAssert(screenLockTimeout >= 0);
        if (self.appBecameInactiveDate && screenLockInterval < screenLockTimeout) {
            // Don't show 'Screen Lock' if 'Screen Lock' timeout hasn't elapsed.
            shouldHaveScreenLock = NO;
        } else {
            // Otherwise, show 'Screen Lock'.
            shouldHaveScreenLock = YES;
        }
    }

    BOOL shouldShowBlockWindow = shouldHaveScreenProtection || shouldHaveScreenLock;
    DDLogVerbose(@"%@, shouldHaveScreenProtection: %d, shouldHaveScreenLock: %d, shouldShowBlockWindow: %d",
        self.logTag,
        shouldHaveScreenProtection,
        shouldHaveScreenLock,
        shouldShowBlockWindow);
    self.screenBlockingWindow.hidden = !shouldShowBlockWindow;

    if (shouldHaveScreenLock) {
        if (!self.isShowingScreenLockUI) {
            self.isShowingScreenLockUI = YES;

            [OWSScreenLock.sharedManager tryToUnlockScreenLockWithSuccess:^{
                DDLogInfo(@"%@ unlock screen lock succeeded.", self.logTag);
                self.isShowingScreenLockUI = NO;
                self.hasUnlockedScreenLock = YES;
                [self ensureScreenProtection];
            }
                failure:^(NSError *error) {
                    DDLogInfo(@"%@ unlock screen lock failed.", self.logTag);
                    self.isShowingScreenLockUI = NO;

                    [self showScreenLockFailureAlertWithMessage:error.localizedDescription];
                }
                cancel:^{
                    DDLogInfo(@"%@ unlock screen lock cancelled.", self.logTag);
                    self.isShowingScreenLockUI = NO;

                    [self showScreenLockFailureAlertWithMessage:
                              NSLocalizedString(@"SCREEN_LOCK_UNLOCK_CANCELLED",
                                  @"Message for alert indicating that screen lock unlock was cancelled.")];
                }];
        }
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

@end

NS_ASSUME_NONNULL_END
