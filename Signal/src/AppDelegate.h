//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const AppDelegateStoryboardMain;

extern NSString *const kURLSchemeSGNLKey;
extern NSString *const kURLHostTransferPrefix;
extern NSString *const kURLHostLinkDevicePrefix;

extern NSString *const kAppLaunchesAttemptedKey;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

// This public interface is only needed for Swift bridging.

@property (nonatomic, readwrite) NSTimeInterval launchStartedAt;

@property (nonatomic, readwrite) BOOL areVersionMigrationsComplete;

@property (nonatomic, readwrite) BOOL didAppLaunchFail;
@property (nonatomic, readwrite) BOOL shouldKillAppWhenBackgrounded;

@end

NS_ASSUME_NONNULL_END
