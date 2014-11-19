//
//  TSAccountManagement.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSConstants.h"
#import "TSNumberVerifier.h"

typedef void(^codeVerifierBlock)(TSNumberVerifier *numberVerifier);

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

/**
 *  Request a verification challenge
 *
 *  @param phoneNumber  phone number to send verification challenge to
 *  @param transport    sms or voice call
 *  @param successBlock block to execute on success of request
 *  @param failureBlock block to execute on failure of request
 */

+ (void)registerWithPhoneNumber:(NSString*)phoneNumber overTransport:(VerificationTransportType)transport success:(codeVerifierBlock)success failure:(failedRegistrationRequestBlock)failureBlock;

/**
 *  Register's the device's push notification token with the server
 *
 *  @param pushToken Apple's Push Token
 */

+ (void)registerForPushNotifications:(NSData*)pushToken success:(successCompletionBlock)success failure:(failedVerificationBlock)failureBlock;

#endif

@end
