//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const NSNotificationNameRegistrationStateDidChange;
extern NSNotificationName const NSNotificationNameOnboardingStateDidChange;
extern NSString *const TSRemoteAttestationAuthErrorKey;
extern NSNotificationName const NSNotificationNameLocalNumberDidChange;

@class AnyPromise;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;
@class SignalServiceAddress;
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
@property (nonatomic, nullable) NSUUID *pniAwaitingVerification;

#pragma mark - Initializers

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

@property (readonly, nullable) NSUUID *localPni;

- (nullable NSUUID *)localPniWithTransaction:(SDSAnyReadTransaction *)transaction NS_SWIFT_NAME(pni(with:));

@property (readonly, nullable, class) SignalServiceAddress *localAddress;
@property (readonly, nullable) SignalServiceAddress *localAddress;

+ (nullable SignalServiceAddress *)localAddressWithTransaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(localAddress(with:));
- (nullable SignalServiceAddress *)localAddressWithTransaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(localAddress(with:));

- (nullable NSDate *)registrationDateWithTransaction:(SDSAnyReadTransaction *)transaction;

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

- (nullable NSString *)storedDeviceName;
- (void)setStoredDeviceName:(NSString *)deviceName transaction:(SDSAnyWriteTransaction *)transaction;

- (UInt32)storedDeviceId;
- (UInt32)storedDeviceIdWithTransaction:(SDSAnyReadTransaction *)transaction;

/// Onboarding state
- (BOOL)isOnboarded;
- (BOOL)isOnboardedWithTransaction:(SDSAnyReadTransaction *)transaction;
- (void)setIsOnboarded:(BOOL)isOnboarded transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)isDiscoverableByPhoneNumber;
- (BOOL)hasDefinedIsDiscoverableByPhoneNumber;
- (void)setIsDiscoverableByPhoneNumber:(BOOL)isDiscoverableByPhoneNumber
                  updateStorageService:(BOOL)updateStorageService
                           transaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - Register with phone number

// Called once registration is complete - meaning the following have succeeded:
// - obtained signal server credentials
// - uploaded pre-keys
// - uploaded push tokens
- (void)didRegister;
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
- (void)setIsDeregistered:(BOOL)isDeregistered;

#pragma mark - Transfer

@property (nonatomic) BOOL isTransferInProgress;
@property (nonatomic) BOOL wasTransferred;

#pragma mark - Re-registration

// Re-registration is the process of re-registering _with the same phone number_.

// Returns YES on success.
- (BOOL)resetForReregistration;
- (nullable NSString *)reregistrationPhoneNumber;
- (nullable NSUUID *)reregistrationUUID;
@property (nonatomic, readonly) BOOL isReregistering;

#pragma mark - Change Phone Number

- (void)updateLocalPhoneNumber:(NSString *)phoneNumber
                           aci:(NSUUID *)aci
                           pni:(NSUUID *_Nullable)pni
    shouldUpdateStorageService:(BOOL)shouldUpdateStorageService
                   transaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(updateLocalPhoneNumber(_:aci:pni:shouldUpdateStorageService:transaction:));

#pragma mark - Manual Message Fetch

- (BOOL)isManualMessageFetchEnabled;
- (void)setIsManualMessageFetchEnabled:(BOOL)value;

#ifdef TESTABLE_BUILD
- (void)registerForTestsWithLocalNumber:(NSString *)localNumber uuid:(NSUUID *)uuid;
- (void)registerForTestsWithLocalNumber:(NSString *)localNumber uuid:(NSUUID *)uuid pni:(NSUUID *_Nullable)pni;
#endif

@end

NS_ASSUME_NONNULL_END
