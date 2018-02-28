//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSVerifyCodeRequest.h"
#import "TSAccountManager.h"
#import "TSAttributes.h"
#import "TSConstants.h"

@implementation TSVerifyCodeRequest

- (TSRequest *)initWithVerificationCode:(NSString *)verificationCode
                              forNumber:(NSString *)phoneNumber
                           signalingKey:(NSString *)signalingKey
                                authKey:(NSString *)authKey {
    self = [super
        initWithURL:[NSURL URLWithString:[NSString
                                             stringWithFormat:@"%@/code/%@", textSecureAccountsAPI, verificationCode]]];

    _numberToValidate = phoneNumber;

    self.parameters =
        [TSAttributes attributesWithSignalingKey:signalingKey serverAuthToken:authKey manualMessageFetching:NO];

    [self setHTTPMethod:@"PUT"];

    return self;
}

@end
