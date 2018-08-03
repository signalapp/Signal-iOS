//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <RelayMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class HomeViewController;

@interface ProfileViewController : OWSViewController

- (instancetype)init NS_UNAVAILABLE;

+ (BOOL)shouldDisplayProfileViewOnLaunch;

+ (void)presentForAppSettings:(UINavigationController *)navigationController;
+ (void)presentForRegistration:(UINavigationController *)navigationController;
+ (void)presentForUpgradeOrNag:(HomeViewController *)presentingController NS_SWIFT_NAME(presentForUpgradeOrNag(from:));

@end

NS_ASSUME_NONNULL_END
