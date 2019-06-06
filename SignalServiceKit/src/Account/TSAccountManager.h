//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TSRegistrationErrorDomain;
extern NSString *const TSRegistrationErrorUserInfoHTTPStatus;
extern NSString *const RegistrationStateDidChangeNotification;
extern NSString *const kNSNotificationName_LocalNumberDidChange;

@class AnyPromise;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class TSNetworkManager;

typedef NS_ENUM(NSUInteger, OWSRegistrationState) {
    OWSRegistrationState_Unregistered,
    OWSRegistrationState_PendingBackupRestore,
    OWSRegistrationState_Registered,
    OWSRegistrationState_Deregistered,
    OWSRegistrationState_Reregistering,
};

@interface TSAccountManager : NSObject

@property (nonatomic, nullable) NSString *phoneNumberAwaitingVerification;

#pragma mark - Initializers

+ (instancetype)sharedInstance;

- (OWSRegistrationState)registrationState;

/**
 *  Returns if a user is registered or not
 *
 *  @return registered or not
 */
- (BOOL)isRegistered;
- (BOOL)isRegisteredAndReady;

/**
 *  Returns current phone number for this device, which may not yet have been registered.
 *
 *  @return E164 formatted phone number
 */
+ (nullable NSString *)localNumber;
- (nullable NSString *)localNumber;

// A variant of localNumber that never opens a "sneaky" transaction.
- (nullable NSString *)storedOrCachedLocalNumber:(SDSAnyReadTransaction *)transaction;

/**
 *  Symmetric key that's used to encrypt message payloads from the server,
 *
 *  @return signaling key
 */
- (nullable NSString *)storedSignalingKey;

/**
 *  The server auth token allows the Signal client to connect to the Signal server
 *
 *  @return server authentication token
 */
- (nullable NSString *)storedServerAuthToken;

/**
 *  The registration ID is unique to an installation of TextSecure, it allows to know if the app was reinstalled
 *
 *  @return registrationID;
 */
- (uint32_t)getOrGenerateRegistrationId;
- (uint32_t)getOrGenerateRegistrationIdWithTransaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - Register with phone number

- (void)registerWithPhoneNumber:(NSString *)phoneNumber
                   captchaToken:(nullable NSString *)captchaToken
                        success:(void (^)(void))successBlock
                        failure:(void (^)(NSError *error))failureBlock
                smsVerification:(BOOL)isSMS;

- (void)verifyAccountWithCode:(NSString *)verificationCode
                          pin:(nullable NSString *)pin
                      success:(void (^)(void))successBlock
                      failure:(void (^)(NSError *error))failureBlock;

// Called once registration is complete - meaning the following have succeeded:
// - obtained signal server credentials
// - uploaded pre-keys
// - uploaded push tokens
- (void)didRegister;

#if TARGET_OS_IPHONE

/**
 *  Register's the device's push notification token with the server
 *
 *  @param pushToken Apple's Push Token
 */
- (void)registerForPushNotificationsWithPushToken:(NSString *)pushToken
                                        voipToken:(NSString *)voipToken
                                          success:(void (^)(void))successHandler
                                          failure:(void (^)(NSError *error))failureHandler
    NS_SWIFT_NAME(registerForPushNotifications(pushToken:voipToken:success:failure:));

#endif

+ (void)unregisterTextSecureWithSuccess:(void (^)(void))success failure:(void (^)(NSError *error))failureBlock;

#pragma mark - De-Registration

// De-registration reflects whether or not the "last known contact"
// with the service was:
//
// * A 403 from the service, indicating de-registration.
// * A successful auth'd request _or_ websocket connection indicating
//   valid registration.
- (BOOL)isDeregistered;
- (void)setIsDeregistered:(BOOL)isDeregistered;

- (BOOL)hasPendingBackupRestoreDecision;
- (void)setHasPendingBackupRestoreDecision:(BOOL)value;

#pragma mark - Re-registration

// Re-registration is the process of re-registering _with the same phone number_.

// Returns YES on success.
- (BOOL)resetForReregistration;
- (nullable NSString *)reregistrationPhoneNumber;
- (BOOL)isReregistering;

#pragma mark - Manual Message Fetch

- (BOOL)isManualMessageFetchEnabled;
- (void)setIsManualMessageFetchEnabled:(BOOL)value;

#ifdef DEBUG
- (void)registerForTestsWithLocalNumber:(NSString *)localNumber;
#endif

- (AnyPromise *)updateAccountAttributes __attribute__((warn_unused_result));

// This should only be used during the registration process.
- (AnyPromise *)performUpdateAccountAttributes __attribute__((warn_unused_result));

@end

NS_ASSUME_NONNULL_END
