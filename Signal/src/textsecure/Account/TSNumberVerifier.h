//
//  TSNumberVerifier.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 31/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSConstants.h"

typedef NS_ENUM(NSUInteger, TSRegistrationFailure) {
    kTSRegistrationFailureAuthentication,
    kTSRegistrationFailureNetwork,
    kTSRegistrationFailureRateLimit,
    kTSRegistrationFailureWrongCode,
    kTSRegistrationFailureAlreadyRegistered,
    kTSRegistrationFailurePrekeys,
    kTSRegistrationFailurePushID,
    kTSRegistrationFailureRequest
};

typedef void(^failedVerificationBlock)(TSRegistrationFailure failureType);

@interface TSNumberVerifier : NSObject

/**
 *  Verify verification challenge code. To be called only after registerWithPhoneNumber succeeded
 *
 *  @param verificationCode the verification code received
 *  @param successBlock     block to execute on success of request
 *  @param failureBlock     block to execute on failure of request
 */

- (void)verifyCode:(NSString*)verificationCode success:(successCompletionBlock)successBlock failure:(failedVerificationBlock)failureBlock;

+ (void)registerPhoneNumber:(NSString*)phoneNumber withRedPhoneToken:(NSString*)registrationToken success:(successCompletionBlock)successBlock failure:(failedVerificationBlock)failureBlock;

@end
