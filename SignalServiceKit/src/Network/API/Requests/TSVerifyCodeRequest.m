//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSAccountManager.h"
#import "TSAttributes.h"
#import "TSConstants.h"
#import "TSVerifyCodeRequest.h"

@implementation TSVerifyCodeRequest

- (TSRequest *)initWithVerificationCode:(NSString *)verificationCode
                              forNumber:(NSString *)phoneNumber
                           signalingKey:(NSString *)signalingKey
                                authKey:(NSString *)authKey {
    self = [super
        initWithURL:[NSURL URLWithString:[NSString
                                             stringWithFormat:@"%@/code/%@", textSecureAccountsAPI, verificationCode]]];

    NSDictionary *attributes =
        [TSAttributes attributesWithSignalingKey:signalingKey serverAuthToken:authKey manualMessageFetching:NO];

    _numberToValidate = phoneNumber;
    [self.parameters addEntriesFromDictionary:attributes];

    [self setHTTPMethod:@"PUT"];

    return self;
}

@end
