//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface FingerprintViewController : OWSViewController

+ (void)presentFromViewController:(UIViewController *)viewController recipientId:(NSString *)recipientId;

@end

NS_ASSUME_NONNULL_END
