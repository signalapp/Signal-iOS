//
//  TSSendSMSVerificationRequest.m
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 9/29/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"
#import "NSString+escape.h"

#import "TSRequestVerificationCodeRequest.h"

@implementation TSRequestVerificationCodeRequest

- (TSRequest*)initRequestForPhoneNumber:(NSString*)phoneNumber transport:(VerificationTransportType)transport{
    
    self = [super initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/code/%@", textSecureAccountsAPI, (transport == kSMSVerification)? @"sms" : @"voice", [phoneNumber escape]]]];
    
    [self setHTTPMethod:@"GET"];
    
    return self;
}

@end
