//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const NSNotificationNameRegistrationStateDidChange;
extern NSNotificationName const NSNotificationNameOnboardingStateDidChange;
extern NSString *const TSRemoteAttestationAuthErrorKey;
extern NSNotificationName const NSNotificationNameLocalNumberDidChange;

extern NSString *const TSAccountManager_RegisteredNumberKey;
extern NSString *const TSAccountManager_RegistrationDateKey;
extern NSString *const TSAccountManager_RegisteredUUIDKey;
extern NSString *const TSAccountManager_RegisteredPNIKey;
extern NSString *const TSAccountManager_IsDeregisteredKey;
extern NSString *const TSAccountManager_ReregisteringPhoneNumberKey;
extern NSString *const TSAccountManager_ReregisteringUUIDKey;
extern NSString *const TSAccountManager_IsOnboardedKey;
extern NSString *const TSAccountManager_IsTransferInProgressKey;
extern NSString *const TSAccountManager_WasTransferredKey;
extern NSString *const TSAccountManager_HasPendingRestoreDecisionKey;
extern NSString *const TSAccountManager_IsDiscoverableByPhoneNumberKey;
extern NSString *const TSAccountManager_LastSetIsDiscoverableByPhoneNumberKey;

extern NSString *const TSAccountManager_UserAccountCollection;
extern NSString *const TSAccountManager_ServerAuthTokenKey;
extern NSString *const TSAccountManager_ManualMessageFetchKey;

extern NSString *const TSAccountManager_DeviceIdKey;

@class AnyPromise;
@class E164ObjC;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;
@class SignalServiceAddress;
@class TSAccountState;
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

/// This property should only be accessed while @synchronized on self.
///
/// Generally, it will nil until loaded for the first time (while warming
/// the caches) and non-nil after.
///
/// There's an important exception: we discard (but don't reload) the cache
/// when notified of a cross-process write.
@property (nonatomic, nullable) TSAccountState *cachedAccountState;

@property (nonatomic, readonly) SDSKeyValueStore *keyValueStore;

@property (nonatomic, nullable) NSString *phoneNumberAwaitingVerification;
@property (nonatomic, nullable) NSUUID *uuidAwaitingVerification;
@property (nonatomic, nullable) NSUUID *pniAwaitingVerification;

#pragma mark - Initializers

- (void)warmCaches;

- (TSAccountState *)getOrLoadAccountStateWithTransaction:(SDSAnyReadTransaction *)transaction;
- (TSAccountState *)getOrLoadAccountStateWithSneakyTransaction;

- (TSAccountState *)loadAccountStateWithTransaction:(SDSAnyReadTransaction *)transaction;
- (TSAccountState *)loadAccountStateWithSneakyTransaction;

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

- (BOOL)isRegisteredAndReadyWithTransaction:(SDSAnyReadTransaction *)transaction;

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

- (nullable NSUUID *)localUuidWithTransaction:(SDSAnyReadTransaction *)transaction NS_SWIFT_NAME(localUuid(with:));

@property (readonly, nullable) NSUUID *localPni;

- (nullable NSUUID *)localPniWithTransaction:(SDSAnyReadTransaction *)transaction NS_SWIFT_NAME(localPni(with:));

@property (readonly, nullable, class) SignalServiceAddress *localAddress;
@property (readonly, nullable) SignalServiceAddress *localAddress;

+ (nullable SignalServiceAddress *)localAddressWithTransaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(localAddress(with:));
- (nullable SignalServiceAddress *)localAddressWithTransaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(localAddress(with:));

- (nullable NSDate *)registrationDateWithTransaction:(SDSAnyReadTransaction *)transaction;

/**
 *  The server auth token allows the Signal client to connect to the Signal server
 *
 *  @return server authentication token
 */
- (nullable NSString *)storedServerAuthToken;
- (nullable NSString *)storedServerAuthTokenWithTransaction:(SDSAnyReadTransaction *)transaction;
- (void)setStoredServerAuthToken:(NSString *)authToken
                        deviceId:(UInt32)deviceId
                     transaction:(SDSAnyWriteTransaction *)transaction;

- (UInt32)storedDeviceId;
- (UInt32)storedDeviceIdWithTransaction:(SDSAnyReadTransaction *)transaction;

/// Onboarding state
- (BOOL)isOnboarded;
- (BOOL)isOnboardedWithTransaction:(SDSAnyReadTransaction *)transaction;
- (void)setIsOnboarded:(BOOL)isOnboarded transaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - Register with phone number

// Called once registration is complete - meaning the following have succeeded:
// - obtained signal server credentials
// - uploaded pre-keys
// - uploaded push tokens
- (void)didRegister;
- (void)didRegisterPrimaryWithE164:(E164ObjC *)e164
                               aci:(NSUUID *)aci
                               pni:(NSUUID *)pni
                         authToken:(NSString *)authToken
                       transaction:(SDSAnyWriteTransaction *)transaction;
- (void)recordUuidForLegacyUser:(NSUUID *)uuid NS_SWIFT_NAME(recordUuidForLegacyUser(_:));

#pragma mark - De-Registration

/// Checks if the account is "deregistered".
///
/// An account is deregistered if a device transfer is in progress, a device
/// transfer was just completed to another device, or we received an HTTP
/// 401/403 error that indicates we're no longer registered.
///
/// If an account is deregistered due to an HTTP 401/403 error, the user
/// should complete re-registration to re-mark the account as "registered".
- (BOOL)isDeregistered;
- (BOOL)isDeregisteredWithTransaction:(SDSAnyReadTransaction *)transaction;
- (void)setIsDeregistered:(BOOL)isDeregistered;

#pragma mark - Transfer

@property (nonatomic) BOOL isTransferInProgress;
@property (nonatomic) BOOL wasTransferred;

#pragma mark - Re-registration

// Re-registration is the process of re-registering _with the same phone number_.

// Returns YES on success.
- (BOOL)resetForReregistration;
- (void)resetForReregistrationWithLocalPhoneNumber:(E164ObjC *)localPhoneNumber
                                          localAci:(NSUUID *)localAci
                                  wasPrimaryDevice:(BOOL)wasPrimaryDevice
                                       transaction:(SDSAnyWriteTransaction *)transaction;
- (nullable NSString *)reregistrationPhoneNumber;
- (nullable NSUUID *)reregistrationUUID;
@property (nonatomic, readonly) BOOL isReregistering;

#pragma mark - Change Phone Number

/// Update local state concerning the phone number.
///
/// Note that the `pni` parameter is nullable to support legacy behavior.
///
// PNI TODO: once all devices are PNI-capable, remove PNI nullability here.
- (void)updateLocalPhoneNumber:(E164ObjC *)e164
                           aci:(NSUUID *)uuid
                           pni:(NSUUID *_Nullable)pni
                   transaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - Manual Message Fetch

- (BOOL)isManualMessageFetchEnabled;
- (BOOL)isManualMessageFetchEnabled:(SDSAnyReadTransaction *)transaction;
- (void)setIsManualMessageFetchEnabled:(BOOL)value;
- (void)setIsManualMessageFetchEnabled:(BOOL)value transaction:(SDSAnyWriteTransaction *)transaction;

#ifdef TESTABLE_BUILD
- (void)registerForTestsWithLocalNumber:(NSString *)localNumber uuid:(NSUUID *)uuid;
- (void)registerForTestsWithLocalNumber:(NSString *)localNumber uuid:(NSUUID *)uuid pni:(NSUUID *_Nullable)pni;
#endif

@end

NS_ASSUME_NONNULL_END
