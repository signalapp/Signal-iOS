//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

@interface FingerprintViewController : OWSViewController

+ (void)presentFromViewController:(UIViewController *)viewController address:(SignalServiceAddress *)address;

@end

NS_ASSUME_NONNULL_END
