//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface FingerprintViewController : UIViewController

+ (void)showVerificationViewFromViewController:(UIViewController *)viewController recipientId:(NSString *)recipientId;

@end

NS_ASSUME_NONNULL_END
