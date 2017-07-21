//
//  TSRequestVerificationCodeRequest.m
//  Signal
//
//  Created by Frederic Jacobs on 02/12/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"
#import "TSRequestVerificationCodeRequest.h"

@implementation TSRequestVerificationCodeRequest

- (TSRequest *)initWithPhoneNumber:(NSString *)phoneNumber transport:(TSVerificationTransport)transport {
    self = [super initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/code/%@?client=ios",
                                                                              textSecureAccountsAPI,
                                                                              [self stringForTransport:transport],
                                                                              phoneNumber]]];

    self.parameters = nil;
    [self setHTTPMethod:@"GET"];

    return self;
}

- (NSString *)stringForTransport:(TSVerificationTransport)transport {
    switch (transport) {
        case TSVerificationTransportSMS:
            return @"sms";
        case TSVerificationTransportVoice:
            return @"voice";
        default:
            @throw [NSException
                exceptionWithName:@"Unsupported transport exception"
                           reason:[NSString stringWithFormat:@"Transport %u in enum is not supported.", transport]
                         userInfo:nil];
    }
}

- (void)makeAuthenticatedRequest {
}

@end
