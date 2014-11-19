//
//  TSServerCodeVerificationRequest.h
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 10/12/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

@interface TSServerCodeVerificationRequest : TSRequest

- (TSRequest*) initWithVerificationCode:(NSString*)verificationCode signalingKey:(NSString*)signalingKey authKey:(NSString*)authKey;

@property (nonatomic, copy) NSString *numberToValidate;

@end

