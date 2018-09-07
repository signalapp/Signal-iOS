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
typedef void (^AppActiveBlock)(void);

NSString *NSStringForUIApplicationState(UIApplicationState value);

@class OWSAES256Key;

@protocol SSKKeychainStorage;

@protocol AppContext <NSObject>

@property (nonatomic, readonly) BOOL isMainApp;
@property (nonatomic, readonly) BOOL isMainAppAndActive;

// Whether the user is using a right-to-left language like Arabic.
@property (nonatomic, readonly) BOOL isRTL;

@property (nonatomic, readonly) BOOL isRunningTests;

@property (atomic, nullable) UIWindow *mainWindow;

// Unlike UIApplication.applicationState, this is thread-safe.
// It contains the "last known" application state.
//
// Because it is updated in response to "will/did-style" events, it is
// conservative and skews toward less-active and not-foreground:
//
// * It doesn't report "is active" until the app is active
//   and reports "inactive" as soon as it _will become_ inactive.
// * It doesn't report "is foreground (but inactive)" until the app is
//   foreground & inactive and reports "background" as soon as it _will
//   enter_ background.
//
// This conservatism is useful, since we want to err on the side of
// caution when, for example, we do work that should only be done
// when the app is foreground and active.
@property (atomic, readonly) UIApplicationState reportedApplicationState;

// A convenience accessor for reportedApplicationState.
//
// This method is thread-safe.
- (BOOL)isInBackground;

// A convenience accessor for reportedApplicationState.
//
// This method is thread-safe.
- (BOOL)isAppForegroundAndActive;

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

- (void)runNowOrWhenMainAppIsActive:(AppActiveBlock)block;

@property (atomic, readonly) NSDate *appLaunchTime;

- (id<SSKKeychainStorage>)keychainStorage;

- (NSString *)appDocumentDirectoryPath;

- (NSString *)appSharedDataDirectoryPath;

@end

id<AppContext> CurrentAppContext(void);
void SetCurrentAppContext(id<AppContext> appContext);

void ExitShareExtension(void);

#ifdef DEBUG
void ClearCurrentAppContextForTests(void);
#endif

NS_ASSUME_NONNULL_END
