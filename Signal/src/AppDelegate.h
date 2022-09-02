//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString *const AppDelegateStoryboardMain;

extern NSString *const kURLSchemeSGNLKey;
extern NSString *const kURLHostTransferPrefix;
extern NSString *const kURLHostLinkDevicePrefix;

extern NSString *const kAppLaunchesAttemptedKey;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, readonly) NSTimeInterval launchStartedAt;

@property (nonatomic, readonly) BOOL areVersionMigrationsComplete;

@property (nonatomic, readonly) BOOL didAppLaunchFail;

@end
