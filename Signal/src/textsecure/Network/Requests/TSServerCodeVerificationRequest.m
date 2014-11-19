//
//  TSServerCodeVerificationRequest.m
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 10/12/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"
#import "TSAccountManager.h"
#import "TSServerCodeVerificationRequest.h"

@implementation TSServerCodeVerificationRequest

- (TSRequest*) initWithVerificationCode:(NSString*)verificationCode signalingKey:(NSString*)signalingKey authKey:(NSString*)authKey {
    self = [super initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/%@", textSecureAccountsAPI, @"code", verificationCode]]];
    
    [self.parameters addEntriesFromDictionary:@{@"signalingKey": signalingKey, @"AuthKey": authKey, @"supportsSMS": @FALSE, @"registrationId": [NSString stringWithFormat:@"%i",[TSAccountManager getOrGenerateRegistrationId]]}];
     
    [self setHTTPMethod:@"PUT"];
    
    return self;
}



@end
