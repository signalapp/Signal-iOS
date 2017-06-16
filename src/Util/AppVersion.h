//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface AppVersion : NSObject

@property (nonatomic, readonly) NSString *firstAppVersion;
@property (nonatomic, readonly) NSString *lastAppVersion;
@property (nonatomic, readonly) NSString *currentAppVersion;

// Unlike lastAppVersion, this property isn't updated until
// appLaunchDidComplete is called.
@property (nonatomic, readonly) NSString *lastCompletedLaunchAppVersion;

+ (instancetype)instance;

- (void)appLaunchDidComplete;

- (BOOL)isFirstLaunch;

@end
