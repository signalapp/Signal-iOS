//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@interface CodeVerificationViewController : OWSViewController

- (void)setVerificationCodeAndTryToVerify:(NSString *)verificationCode;

@end

NS_ASSUME_NONNULL_END
