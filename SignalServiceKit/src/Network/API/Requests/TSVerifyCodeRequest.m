//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSVerifyCodeRequest.h"
#import "TSAccountManager.h"
#import "TSAttributes.h"
#import "TSConstants.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSVerifyCodeRequest

- (TSRequest *)initWithVerificationCode:(NSString *)verificationCode
                              forNumber:(NSString *)phoneNumber
                                    pin:(nullable NSString *)pin
                           signalingKey:(NSString *)signalingKey
                                authKey:(NSString *)authKey
{
    self = [super
        initWithURL:[NSURL URLWithString:[NSString
                                             stringWithFormat:@"%@/code/%@", textSecureAccountsAPI, verificationCode]]];

    _numberToValidate = phoneNumber;

    NSMutableDictionary *parameters =
        [[TSAttributes attributesWithSignalingKey:signalingKey serverAuthToken:authKey manualMessageFetching:NO]
            mutableCopy];
    if (pin) {
        OWSAssert(pin.length > 0);
        parameters[@"pin"] = pin;
    }
    self.parameters = parameters;

    [self setHTTPMethod:@"PUT"];

    return self;
}

@end

NS_ASSUME_NONNULL_END
