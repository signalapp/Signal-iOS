//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface CodeVerificationViewController : UIViewController

- (void)setVerificationCodeAndTryToVerify:(NSString *)verificationCode;

@end
