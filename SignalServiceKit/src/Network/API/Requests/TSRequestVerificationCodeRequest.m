//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSRequestVerificationCodeRequest.h"
#import "TSConstants.h"

@implementation TSRequestVerificationCodeRequest

- (TSRequest *)initWithPhoneNumber:(NSString *)phoneNumber transport:(TSVerificationTransport)transport {
    self = [super initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/code/%@?client=ios",
                                                                              textSecureAccountsAPI,
                                                                              [self stringForTransport:transport],
                                                                              phoneNumber]]];
    if (!self) {
        return nil;
    }

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
            OWSRaiseException(@"Unsupported transport exception", @"Transport %u in enum is not supported.", transport);
    }
}

@end
