//
//  TSRegisterWithTokenRequest.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 14/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
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
        [TSAttributes attributesWithSignalingKey:signalingKey serverAuthToken:authKey];

    _numberToValidate = phoneNumber;
    [self.parameters addEntriesFromDictionary:attributes];

    [self setHTTPMethod:@"PUT"];

    return self;
}

@end
