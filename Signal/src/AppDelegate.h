//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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

@property (nonatomic, readonly) NSTimeInterval launchStartedAt;

@property (nonatomic, readwrite) BOOL areVersionMigrationsComplete;

@property (nonatomic, readwrite) BOOL didAppLaunchFail;
@property (nonatomic, readwrite) BOOL shouldKillAppWhenBackgrounded;

- (BOOL)launchToHomeScreenWithLaunchOptions:(NSDictionary *_Nullable)launchOptions
                       instrumentsMonitorId:(unsigned long long)monitorId;

@end

NS_ASSUME_NONNULL_END
