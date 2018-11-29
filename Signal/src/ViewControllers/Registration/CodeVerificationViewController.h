//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class RegistrationController;

@interface CodeVerificationViewController : OWSViewController

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithRegistrationController:(RegistrationController *)registrationController
    NS_DESIGNATED_INITIALIZER;

- (void)setVerificationCodeAndTryToVerify:(NSString *)verificationCode;

@end

NS_ASSUME_NONNULL_END
