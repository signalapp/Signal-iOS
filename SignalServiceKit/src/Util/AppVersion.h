//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@interface AppVersion : NSObject

// The properties are updated immediately after launch.
@property (atomic, readonly) NSString *firstAppVersion;
@property (atomic, readonly) NSString *lastAppVersion;
@property (atomic, readonly) NSString *currentAppVersion;

// There properties aren't updated until appLaunchDidComplete is called.
@property (atomic, readonly) NSString *lastCompletedLaunchAppVersion;
@property (atomic, readonly) NSString *lastCompletedLaunchMainAppVersion;
@property (atomic, readonly) NSString *lastCompletedLaunchSAEAppVersion;

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedInstance;

- (void)mainAppLaunchDidComplete;
- (void)saeLaunchDidComplete;

- (BOOL)isFirstLaunch;

@end
