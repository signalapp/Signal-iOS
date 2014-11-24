//
//  TSRegisterWithTokenRequest.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 14/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"
#import "TSAccountManager.h"
#import "TSRegisterWithTokenRequest.h"

@implementation TSRegisterWithTokenRequest

- (TSRequest*) initWithVerificationToken:(NSString*)verificationCode
                            signalingKey:(NSString*)signalingKey
                                 authKey:(NSString*)authKey
                                  number:(NSString*)number
{
    self = [super initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/token/%@", textSecureAccountsAPI, verificationCode]]];
    
    self.numberToValidate = number;
    
    [self.parameters addEntriesFromDictionary:@{@"signalingKey": signalingKey,
                                                @"AuthKey": authKey,
                                                @"supportsSMS": @"0",
                                                @"registrationId": [NSString stringWithFormat:@"%i",[TSAccountManager getOrGenerateRegistrationId]]}];
    
    [self setHTTPMethod:@"PUT"];
    
    return self;
    
}

@end

