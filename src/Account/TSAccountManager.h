//
//  TSAccountManagement.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSConstants.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const TSRegistrationErrorDomain             = @"TSRegistrationErrorDomain";
static NSString *const TSRegistrationErrorUserInfoHTTPStatus = @"TSHTTPStatus";

@class TSNetworkManager;
@class TSStorageManager;

@interface TSAccountManager : NSObject

#pragma mark - Initializers

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
                        storageManager:(TSStorageManager *)storageManager;

+ (instancetype)sharedInstance;

@property (nonatomic, strong, readonly) TSNetworkManager *networkManager;

/**
 *  Returns if a user is registered or not
 *
 *  @return registered or not
 */
+ (BOOL)isRegistered;

- (void)ifRegistered:(BOOL)isRegistered runAsync:(void (^)())block;

/**
 *  Returns current phone number for this device, which may not yet have been registered.
 *
 *  @return E164 formatted phone number
 */
+ (nullable NSString *)localNumber;

/**
 *  The registration ID is unique to an installation of TextSecure, it allows to know if the app was reinstalled
 *
 *  @return registrationID;
 */

+ (uint32_t)getOrGenerateRegistrationId;

#pragma mark - Register with phone number

+ (void)registerWithPhoneNumber:(NSString *)phoneNumber
                        success:(void (^)())successBlock
                        failure:(void (^)(NSError *error))failureBlock
                smsVerification:(BOOL)isSMS;

+ (void)rerequestSMSWithSuccess:(void (^)())successBlock failure:(void (^)(NSError *error))failureBlock;

+ (void)rerequestVoiceWithSuccess:(void (^)())successBlock failure:(void (^)(NSError *error))failureBlock;

- (void)verifyAccountWithCode:(NSString *)verificationCode
                      success:(void (^)())successBlock
                      failure:(void (^)(NSError *error))failureBlock;

#if TARGET_OS_IPHONE

/**
 *  Register's the device's push notification token with the server
 *
 *  @param pushToken Apple's Push Token
 */
- (void)registerForPushNotificationsWithPushToken:(NSString *)pushToken
                                        voipToken:(NSString *)voipToken
                                          success:(void (^)())successHandler
                                          failure:(void (^)(NSError *error))failureHandler
    NS_SWIFT_NAME(registerForPushNotifications(pushToken:voipToken:success:failure:));

#endif

+ (void)unregisterTextSecureWithSuccess:(void (^)())success failure:(void (^)(NSError *error))failureBlock;

@end

NS_ASSUME_NONNULL_END
