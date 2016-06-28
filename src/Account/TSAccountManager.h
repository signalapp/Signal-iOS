//
//  TSAccountManagement.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSConstants.h"

static NSString *const TSRegistrationErrorDomain             = @"TSRegistrationErrorDomain";
static NSString *const TSRegistrationErrorUserInfoHTTPStatus = @"TSHTTPStatus";

typedef void (^failedBlock)(NSError *error);

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

+ (NSString *)localNumber;

+ (void)didRegister;

/**
 *  The registration ID is unique to an installation of TextSecure, it allows to know if the app was reinstalled
 *
 *  @return registrationID;
 */

+ (uint32_t)getOrGenerateRegistrationId;

#pragma mark - Register with phone number

+ (void)registerWithPhoneNumber:(NSString *)phoneNumber
                        success:(successCompletionBlock)successBlock
                        failure:(failedBlock)failureBlock
                smsVerification:(BOOL)isSMS;

+ (void)rerequestSMSWithSuccess:(successCompletionBlock)successBlock failure:(failedBlock)failureBlock;

+ (void)rerequestVoiceWithSuccess:(successCompletionBlock)successBlock failure:(failedBlock)failureBlock;

+ (void)verifyAccountWithCode:(NSString *)verificationCode
                    pushToken:(NSString *)pushToken
                    voipToken:(NSString *)voipToken
                      success:(successCompletionBlock)successBlock
                      failure:(failedBlock)failureBlock;

#if TARGET_OS_IPHONE

/**
 *  Register's the device's push notification token with the server
 *
 *  @param pushToken Apple's Push Token
 */

+ (void)registerForPushNotifications:(NSString *)pushToken
                           voipToken:(NSString *)voipToken
                             success:(successCompletionBlock)success
                             failure:(failedBlock)failureBlock;

+ (void)obtainRPRegistrationToken:(void (^)(NSString *rpRegistrationToken))success failure:(failedBlock)failureBlock;

#endif

+ (void)unregisterTextSecureWithSuccess:(successCompletionBlock)success failure:(failedBlock)failureBlock;

@end
