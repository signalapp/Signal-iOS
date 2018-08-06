//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@interface AppVersion : NSObject

@property (nonatomic, readonly) NSString *firstAppVersion;
@property (nonatomic, readonly) NSString *lastAppVersion;
@property (nonatomic, readonly) NSString *currentAppVersion;

// Unlike lastAppVersion, this property isn't updated until
// appLaunchDidComplete is called.
@property (nonatomic, readonly) NSString *lastCompletedLaunchAppVersion;
@property (nonatomic, readonly) NSString *lastCompletedLaunchMainAppVersion;
@property (nonatomic, readonly) NSString *lastCompletedLaunchSAEAppVersion;

+ (instancetype)instance;

- (void)mainAppLaunchDidComplete;
- (void)saeLaunchDidComplete;

- (BOOL)isFirstLaunch;

@end
