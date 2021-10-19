//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalUI/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

@interface FingerprintViewController : OWSViewController

+ (void)presentFromViewController:(UIViewController *)viewController address:(SignalServiceAddress *)address;

@end

NS_ASSUME_NONNULL_END
