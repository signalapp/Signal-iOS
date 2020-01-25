//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class ConversationListViewController;
@class SDSKeyValueStore;

@interface ProfileViewController : OWSViewController

+ (SDSKeyValueStore *)keyValueStore;

- (instancetype)init NS_UNAVAILABLE;

+ (BOOL)shouldDisplayProfileViewOnLaunch;

+ (void)presentForAppSettings:(UINavigationController *)navigationController;
+ (void)presentForRegistration:(UINavigationController *)navigationController;
+ (instancetype)forExperienceUpgradeWithCompletionHandler:(void (^)(void))completionHandler;

@end

NS_ASSUME_NONNULL_END
