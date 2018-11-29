//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class RegistrationController;

@interface OWS2FARegistrationViewController : OWSViewController

@property (nonatomic) NSString *verificationCode;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithRegistrationController:(RegistrationController *)registrationController
    NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
