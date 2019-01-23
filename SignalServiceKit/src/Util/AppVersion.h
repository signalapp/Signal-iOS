//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface AppVersion : NSObject

// The properties are updated immediately after launch.
@property (atomic, readonly) NSString *firstAppVersion;
@property (atomic, nullable, readonly) NSString *lastAppVersion;
@property (atomic, readonly) NSString *currentAppVersion;

// There properties aren't updated until appLaunchDidComplete is called.
@property (atomic, nullable, readonly) NSString *lastCompletedLaunchAppVersion;
@property (atomic, nullable, readonly) NSString *lastCompletedLaunchMainAppVersion;
@property (atomic, nullable, readonly) NSString *lastCompletedLaunchSAEAppVersion;

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedInstance;

- (void)mainAppLaunchDidComplete;
- (void)saeLaunchDidComplete;

- (BOOL)isFirstLaunch;

@end

NS_ASSUME_NONNULL_END
