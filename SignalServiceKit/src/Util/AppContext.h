//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef void (^BackgroundTaskExpirationHandler)(void);

@class OWSAES256Key;

@protocol AppContext <NSObject>

- (BOOL)isMainApp;
- (BOOL)isMainAppAndActive;

// Should only be called if isMainApp is YES.
//
// In general, isMainAppAndActive will probably yield more readable code.
- (UIApplicationState)mainApplicationState;

// Should start a background task if isMainApp is YES.
// Should just return UIBackgroundTaskInvalid if isMainApp is NO.
- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithExpirationHandler:
    (BackgroundTaskExpirationHandler)expirationHandler;
// Should be a NOOP if isMainApp is NO.
- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)backgroundTaskIdentifier;

// Should only be called if isMainApp is YES.
- (void)setMainAppBadgeNumber:(NSInteger)value;

<<<<<<< HEAD
- (BOOL)isRTL;

||||||| parent of d1a8c9aa... Respond to CR.
// This should all migrations which do NOT qualify as safeBlockingMigrations:
- (NSArray<OWSDatabaseMigration *> *)allMigrations;

// This should only include migrations which:
//
// a) Do read/write database transactions and therefore would block on the async database
//    view registration.
// b) Will not affect any of the data used by the async database views.
- (NSArray<OWSDatabaseMigration *> *)safeBlockingMigrations;

=======
>>>>>>> d1a8c9aa... Respond to CR.
// Returns the VC that should be used to present alerts, modals, etc.
- (nullable UIViewController *)frontmostViewController;

// Should only be called if isMainApp is YES.
- (void)openSystemSettings;

// Should only be called if isMainApp is YES,
// but should only be necessary to call if isMainApp is YES.
- (void)doMultiDeviceUpdateWithProfileKey:(OWSAES256Key *)profileKey;

- (BOOL)isRunningTests;

@end

id<AppContext> CurrentAppContext(void);
void SetCurrentAppContext(id<AppContext> appContext);

NS_ASSUME_NONNULL_END
