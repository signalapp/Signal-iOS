//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface AppVersion : NSObject

// These properties are global and available immediately
@property (class, atomic, readonly) NSString *hardwareInfoString;
@property (class, atomic, readonly) NSString *iOSVersionString;

// The properties are updated immediately after launch.
@property (atomic, readonly) NSString *firstAppVersion;
@property (atomic, nullable, readonly) NSString *lastAppVersion;

// e.g. v3.14.5
@property (atomic, readonly) NSString *currentAppVersion;
// e.g. v3.14.5.6
@property (atomic, readonly) NSString *currentAppVersionLong;

// There properties aren't updated until appLaunchDidComplete is called.
@property (atomic, nullable, readonly) NSString *lastCompletedLaunchAppVersion;
@property (atomic, nullable, readonly) NSString *lastCompletedLaunchMainAppVersion;
@property (atomic, nullable, readonly) NSString *lastCompletedLaunchSAEAppVersion;
@property (atomic, nullable, readonly) NSString *lastCompletedLaunchNSEAppVersion;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)shared;

- (void)mainAppLaunchDidComplete;
- (void)saeLaunchDidComplete;
- (void)nseLaunchDidComplete;

- (BOOL)isFirstLaunch;

@end

NS_ASSUME_NONNULL_END
