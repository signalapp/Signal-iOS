//
//  TSAccountManagement.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSConstants.h"

static NSString *const TSRegistrationErrorDomain = @"TSRegistrationErrorDomain";
static NSString *const TSRegistrationErrorUserInfoHTTPStatus = @"TSHTTPStatus";

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

typedef void(^failedVerificationBlock)(NSError *error);

@interface TSAccountManager : NSObject

/**
 *  Returns if a user is registered or not
 *
 *  @return registered or not
 */

+ (BOOL)isRegistered;

/**
 *  Returns registered number
 *
 *  @return E164 formatted phone number
 */

+ (NSString*)registeredNumber;

/**
 *  The registration ID is unique to an installation of TextSecure, it allows to know if the app was reinstalled
 *
 *  @return registrationID;
 */

+ (int)getOrGenerateRegistrationId;

/**
 *  Sets the user as registered
 *
 */

+ (void)setRegistered:(BOOL)registered;

#if TARGET_OS_IPHONE

+ (void)registerWithRedPhoneToken:(NSString*)tsToken pushToken:(NSData*)pushToken success:(successCompletionBlock)successBlock failure:(failedVerificationBlock)failureBlock;

/**
 *  Register's the device's push notification token with the server
 *
 *  @param pushToken Apple's Push Token
 */

+ (void)registerForPushNotifications:(NSData*)pushToken success:(successCompletionBlock)success failure:(failedVerificationBlock)failureBlock;

#endif

+ (NSError *)errorForRegistrationFailure:(TSRegistrationFailure)failureType HTTPStatusCode:(long)HTTPStatus;

@end
