//
//  TSRegisterWithTokenRequest.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 14/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

@interface TSRegisterWithTokenRequest : TSRequest

- (instancetype)initWithVerificationToken:(NSString*)verificationCode signalingKey:(NSString*)signalingKey authKey:(NSString*)authKey number:(NSString*)number;

@property NSString *numberToValidate;

@end
