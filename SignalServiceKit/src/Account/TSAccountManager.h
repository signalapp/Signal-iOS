//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TSRegistrationErrorDomain;
extern NSString *const TSRegistrationErrorUserInfoHTTPStatus;
extern NSNotificationName const NSNotificationNameRegistrationStateDidChange;
extern NSString *const TSRemoteAttestationAuthErrorKey;
extern NSString *const kNSNotificationName_LocalNumberDidChange;

@class AnyPromise;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;
@class SignalServiceAddress;
@class TSNetworkManager;
@class TSRequest;

typedef NS_ENUM(NSUInteger, OWSRegistrationState) {
    OWSRegistrationState_Unregistered,
    OWSRegistrationState_PendingBackupRestore,
    OWSRegistrationState_Registered,
    OWSRegistrationState_Deregistered,
    OWSRegistrationState_Reregistering,
};

NSString *NSStringForOWSRegistrationState(OWSRegistrationState value);

@interface TSAccountManager : NSObject

@property (nonatomic, readonly) SDSKeyValueStore *keyValueStore;

@property (nonatomic, nullable) NSString *phoneNumberAwaitingVerification;
@property (nonatomic, nullable) NSUUID *uuidAwaitingVerification;

#pragma mark - Initializers

+ (TSAccountManager *)shared;

- (void)warmCaches;

- (OWSRegistrationState)registrationState;

/**
 *  Returns if a user is registered or not
 *
 *  @return registered or not
 */
@property (readonly) BOOL isRegistered;
@property (readonly) BOOL isRegisteredAndReady;

// useful before account state has been cached, otherwise you should prefer `isRegistered`
- (BOOL)isRegisteredWithTransaction:(SDSAnyReadTransaction *)transaction NS_SWIFT_NAME(isRegistered(transaction:));

/**
 *  Returns current phone number for this device, which may not yet have been registered.
 *
 *  @return E164 formatted phone number
 */
@property (readonly, nullable) NSString *localNumber;
@property (readonly, nullable, class) NSString *localNumber;

- (nullable NSString *)localNumberWithTransaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(localNumber(with:));

@property (readonly, nullable) NSUUID *localUuid;

- (nullable NSUUID *)localUuidWithTransaction:(SDSAnyReadTransaction *)transaction NS_SWIFT_NAME(uuid(with:));

@property (readonly, nullable, class) SignalServiceAddress *localAddress;
@property (readonly, nullable) SignalServiceAddress *localAddress;

+ (nullable SignalServiceAddress *)localAddressWithTransaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(localAddress(with:));
- (nullable SignalServiceAddress *)localAddressWithTransaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(localAddress(with:));

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
- (void)setStoredServerAuthToken:(NSString *)authToken
                        deviceId:(UInt32)deviceId
                     transaction:(SDSAnyWriteTransaction *)transaction;

/**
 *  The registration ID is unique to an installation of TextSecure, it allows to know if the app was reinstalled
 *
 *  @return registrationID;
 */
- (uint32_t)getOrGenerateRegistrationId;
- (uint32_t)getOrGenerateRegistrationIdWithTransaction:(SDSAnyWriteTransaction *)transaction;

- (nullable NSString *)storedDeviceName;
- (void)setStoredDeviceName:(NSString *)deviceName transaction:(SDSAnyWriteTransaction *)transaction;

- (UInt32)storedDeviceId;
- (UInt32)storedDeviceIdWithTransaction:(SDSAnyReadTransaction *)transaction;

/// Onboarding state
- (BOOL)isOnboarded;
- (void)setIsOnboarded:(BOOL)isOnboarded transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)isDiscoverableByPhoneNumber;
- (BOOL)hasDefinedIsDiscoverableByPhoneNumber;
- (void)setIsDiscoverableByPhoneNumber:(BOOL)isDiscoverableByPhoneNumber
                  updateStorageService:(BOOL)updateStorageService
                           transaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - Register with phone number

- (void)verifyAccountWithRequest:(TSRequest *)request
                         success:(void (^)(_Nullable id responseObject))successBlock
                         failure:(void (^)(NSError *error))failureBlock;

// Called once registration is complete - meaning the following have succeeded:
// - obtained signal server credentials
// - uploaded pre-keys
// - uploaded push tokens
- (void)didRegister;
- (void)recordUuidForLegacyUser:(NSUUID *)uuid NS_SWIFT_NAME(recordUuidForLegacyUser(_:));

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

#pragma mark - Transfer

@property (nonatomic) BOOL isTransferInProgress;
@property (nonatomic) BOOL wasTransferred;

#pragma mark - Backup

- (BOOL)hasPendingBackupRestoreDecision;
- (void)setHasPendingBackupRestoreDecision:(BOOL)value;

#pragma mark - Re-registration

// Re-registration is the process of re-registering _with the same phone number_.

// Returns YES on success.
- (BOOL)resetForReregistration;
- (nullable NSString *)reregistrationPhoneNumber;
@property (nonatomic, readonly) BOOL isReregistering;

#pragma mark - Manual Message Fetch

- (BOOL)isManualMessageFetchEnabled;
- (void)setIsManualMessageFetchEnabled:(BOOL)value;

#ifdef TESTABLE_BUILD
- (void)registerForTestsWithLocalNumber:(NSString *)localNumber uuid:(NSUUID *)uuid;
#endif

@end

NS_ASSUME_NONNULL_END
