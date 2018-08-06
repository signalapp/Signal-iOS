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
    OWSAssert(verificationCode.length > 0);
    OWSAssert(phoneNumber.length > 0);
    OWSAssert(signalingKey.length > 0);
    OWSAssert(authKey.length > 0);

    NSURL *url =
        [NSURL URLWithString:[NSString stringWithFormat:@"%@/code/%@", textSecureAccountsAPI, verificationCode]];
    NSDictionary *parameters =
        [TSAttributes attributesWithSignalingKey:signalingKey serverAuthToken:authKey manualMessageFetching:NO pin:pin];
    self = [super initWithURL:url method:@"PUT" parameters:parameters];

    _numberToValidate = phoneNumber;

    return self;
}

@end

NS_ASSUME_NONNULL_END
