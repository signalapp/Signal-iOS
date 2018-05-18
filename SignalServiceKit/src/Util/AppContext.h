//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// These are fired whenever the corresponding "main app" or "app extension"
// notification is fired.
//
// 1. This saves you the work of observing both.
// 2. This allows us to ensure that any critical work (e.g. re-opening
//    databases) has been done before app re-enters foreground, etc.
extern NSString *const OWSApplicationDidEnterBackgroundNotification;
extern NSString *const OWSApplicationWillEnterForegroundNotification;
extern NSString *const OWSApplicationWillResignActiveNotification;
extern NSString *const OWSApplicationDidBecomeActiveNotification;

typedef void (^BackgroundTaskExpirationHandler)(void);

NSString *NSStringForUIApplicationState(UIApplicationState value);

@class OWSAES256Key;

@protocol AppContext <NSObject>

@property (nonatomic, readonly) BOOL isMainApp;
@property (nonatomic, readonly) BOOL isMainAppAndActive;

// Whether the user is using a right-to-left language like Arabic
@property (nonatomic, readonly) BOOL isRTL;

@property (nonatomic, readonly) BOOL isRunningTests;

@property (atomic, nullable) UIWindow *mainWindow;

// Should only be called if isMainApp is YES.
//
// Wherever possible, use isMainAppAndActive or isInBackground instead.
// This should only be used by debugging/logging code.
- (UIApplicationState)mainApplicationState;

// Similar to UIApplicationStateBackground, but works in SAE.
- (BOOL)isInBackground;

// Should start a background task if isMainApp is YES.
// Should just return UIBackgroundTaskInvalid if isMainApp is NO.
- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithExpirationHandler:
    (BackgroundTaskExpirationHandler)expirationHandler;

// Should be a NOOP if isMainApp is NO.
- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)backgroundTaskIdentifier;

// Should be a NOOP if isMainApp is NO.
- (void)ensureSleepBlocking:(BOOL)shouldBeBlocking blockingObjects:(NSArray<id> *)blockingObjects;

// Should only be called if isMainApp is YES.
- (void)setMainAppBadgeNumber:(NSInteger)value;

- (void)setStatusBarStyle:(UIStatusBarStyle)statusBarStyle;
- (void)setStatusBarHidden:(BOOL)isHidden animated:(BOOL)isAnimated;

@property (nonatomic, readonly) CGFloat statusBarHeight;

// Returns the VC that should be used to present alerts, modals, etc.
- (nullable UIViewController *)frontmostViewController;

// Returns nil if isMainApp is NO
@property (nullable, nonatomic, readonly) UIAlertAction *openSystemSettingsAction;

// Should only be called if isMainApp is YES,
// but should only be necessary to call if isMainApp is YES.
- (void)doMultiDeviceUpdateWithProfileKey:(OWSAES256Key *)profileKey;

// Should be a NOOP if isMainApp is NO.
- (void)setNetworkActivityIndicatorVisible:(BOOL)value;

@end

id<AppContext> CurrentAppContext(void);
void SetCurrentAppContext(id<AppContext> appContext);

void ExitShareExtension(void);

NS_ASSUME_NONNULL_END
