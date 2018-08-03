//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface AppUpdateNag : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedInstance;

- (void)showAppUpgradeNagIfNecessary;

@end
