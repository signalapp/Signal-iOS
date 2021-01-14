//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSAccountManager.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "NSNotificationCenter+OWS.h"
#import "NSURLSessionDataTask+OWS_HTTP.h"
#import "OWSError.h"
#import "OWSRequestFactory.h"
#import "ProfileManagerProtocol.h"
#import "RemoteAttestation.h"
#import "SSKEnvironment.h"
#import "SSKSessionStore.h"
#import "TSNetworkManager.h"
#import "TSPreKeyManager.h"
#import <AFNetworking/AFURLResponseSerialization.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSSocketManager.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSRegistrationErrorDomain = @"TSRegistrationErrorDomain";
NSString *const TSRegistrationErrorUserInfoHTTPStatus = @"TSHTTPStatus";
NSNotificationName const NSNotificationNameRegistrationStateDidChange = @"NSNotificationNameRegistrationStateDidChange";
NSString *const TSRemoteAttestationAuthErrorKey = @"TSRemoteAttestationAuth";
NSString *const kNSNotificationName_LocalNumberDidChange = @"kNSNotificationName_LocalNumberDidChange";

NSString *const TSAccountManager_RegisteredNumberKey = @"TSStorageRegisteredNumberKey";
NSString *const TSAccountManager_RegisteredUUIDKey = @"TSStorageRegisteredUUIDKey";
NSString *const TSAccountManager_IsDeregisteredKey = @"TSAccountManager_IsDeregisteredKey";
NSString *const TSAccountManager_ReregisteringPhoneNumberKey = @"TSAccountManager_ReregisteringPhoneNumberKey";
NSString *const TSAccountManager_LocalRegistrationIdKey = @"TSStorageLocalRegistrationId";
NSString *const TSAccountManager_IsOnboardedKey = @"TSAccountManager_IsOnboardedKey";
NSString *const TSAccountManager_IsTransferInProgressKey = @"TSAccountManager_IsTransferInProgressKey";
NSString *const TSAccountManager_WasTransferredKey = @"TSAccountManager_WasTransferredKey";
NSString *const TSAccountManager_HasPendingRestoreDecisionKey = @"TSAccountManager_HasPendingRestoreDecisionKey";
NSString *const TSAccountManager_IsDiscoverableByPhoneNumber = @"TSAccountManager_IsDiscoverableByPhoneNumber";

NSString *const TSAccountManager_UserAccountCollection = @"TSStorageUserAccountCollection";
NSString *const TSAccountManager_ServerAuthToken = @"TSStorageServerAuthToken";
NSString *const TSAccountManager_ServerSignalingKey = @"TSStorageServerSignalingKey";
NSString *const TSAccountManager_ManualMessageFetchKey = @"TSAccountManager_ManualMessageFetchKey";

NSString *const TSAccountManager_DeviceName = @"TSAccountManager_DeviceName";
NSString *const TSAccountManager_DeviceId = @"TSAccountManager_DeviceId";

NSString *NSStringForOWSRegistrationState(OWSRegistrationState value)
{
    switch (value) {
        case OWSRegistrationState_Unregistered:
            return @"Unregistered";
        case OWSRegistrationState_PendingBackupRestore:
            return @"PendingBackupRestore";
        case OWSRegistrationState_Registered:
            return @"Registered";
        case OWSRegistrationState_Deregistered:
            return @"Deregistered";
        case OWSRegistrationState_Reregistering:
            return @"Reregistering";
    }
}

// A cache of frequently-accessed database state.
//
// * Instances of TSAccountState are immutable.
// * None of this state should change often.
// * Whenever any of this state changes, we reload all of it.
//
// This cache changes all of its properties in lockstep, which
// helps ensure consistency.  e.g. isRegistered is true IFF
// localNumber is non-nil.
@interface TSAccountState : NSObject

@property (nonatomic, readonly, nullable) NSString *localNumber;
@property (nonatomic, readonly, nullable) NSUUID *localUuid;
@property (nonatomic, readonly, nullable) NSString *reregistrationPhoneNumber;

@property (nonatomic, readonly) BOOL isRegistered;
@property (nonatomic, readonly) BOOL isDeregistered;
@property (nonatomic, readonly) BOOL isOnboarded;
@property (nonatomic, readonly) BOOL isDiscoverableByPhoneNumber;
@property (nonatomic, readonly) BOOL hasDefinedIsDiscoverableByPhoneNumber;

@property (nonatomic, readonly) BOOL isTransferInProgress;
@property (nonatomic, readonly) BOOL wasTransferred;

@property (nonatomic, readonly, nullable) NSString *serverSignalingKey;
@property (nonatomic, readonly, nullable) NSString *serverAuthToken;

@property (nonatomic, readonly, nullable) NSString *deviceName;
@property (nonatomic, readonly) UInt32 deviceId;

@end

#pragma mark -

@implementation TSAccountState

- (instancetype)initWithTransaction:(SDSAnyReadTransaction *)transaction keyValueStore:(SDSKeyValueStore *)keyValueStore
{
    OWSAssertDebug(transaction != nil);
    OWSAssertDebug(keyValueStore != nil);

    self = [super init];
    if (!self) {
        return self;
    }

    _localNumber = [keyValueStore getString:TSAccountManager_RegisteredNumberKey transaction:transaction];
    NSString *_Nullable uuidString = [keyValueStore getString:TSAccountManager_RegisteredUUIDKey
                                                  transaction:transaction];
    _localUuid = (uuidString != nil ? [[NSUUID alloc] initWithUUIDString:uuidString] : nil);
    _reregistrationPhoneNumber = [keyValueStore getString:TSAccountManager_ReregisteringPhoneNumberKey
                                              transaction:transaction];
    _isDeregistered = [keyValueStore getBool:TSAccountManager_IsDeregisteredKey
                                defaultValue:NO
                                 transaction:transaction];
    _serverSignalingKey = [keyValueStore getString:TSAccountManager_ServerSignalingKey transaction:transaction];
    _serverAuthToken = [keyValueStore getString:TSAccountManager_ServerAuthToken transaction:transaction];

    _deviceName = [keyValueStore getString:TSAccountManager_DeviceName transaction:transaction];
    _deviceId = [keyValueStore getUInt32:TSAccountManager_DeviceId
                            defaultValue:1 // lazily migrate legacy primary devices
                             transaction:transaction];
    _isOnboarded = [keyValueStore getBool:TSAccountManager_IsOnboardedKey defaultValue:NO transaction:transaction];


    // When we enable the ability to change whether you're discoverable
    // by phone number, new registrations must not be discoverable by
    // default. In order to accomodate this, the default "isDiscoverable"
    // flag will be NO until you have successfully registered (aka defined
    // a local phone number).
    BOOL isDiscoverableByDefault = YES;
    if (SSKFeatureFlags.phoneNumberDiscoverability) {
        isDiscoverableByDefault = self.isRegistered;
    }

    _isDiscoverableByPhoneNumber = [keyValueStore getBool:TSAccountManager_IsDiscoverableByPhoneNumber
                                             defaultValue:isDiscoverableByDefault
                                              transaction:transaction];
    _hasDefinedIsDiscoverableByPhoneNumber = [keyValueStore hasValueForKey:TSAccountManager_IsDiscoverableByPhoneNumber
                                                               transaction:transaction];

    _isTransferInProgress = [keyValueStore getBool:TSAccountManager_IsTransferInProgressKey
                                      defaultValue:NO
                                       transaction:transaction];
    _wasTransferred = [keyValueStore getBool:TSAccountManager_WasTransferredKey
                                defaultValue:NO
                                 transaction:transaction];

    return self;
}

- (BOOL)isRegistered
{
    return nil != self.localNumber;
}

- (BOOL)isReregistering
{
    return nil != self.reregistrationPhoneNumber;
}

- (void)log
{
    OWSLogInfo(@"isRegistered: %d", self.isRegistered);
    OWSLogInfo(@"isDeregistered: %d", self.isDeregistered);
}

@end

#pragma mark -

// We use @synchronized and db transactions often within this class.
// There's a risk of deadlock if we try to @synchronize within a transaction
// while another thread is trying to open a transaction while @synchronized.
// To avoid deadlocks, we follow these guidelines:
//
// * Don't use either unless necessary.
// * Only use one if possible.
// * If both must be used, only @synchronize within a transaction.
//   _Never_ open a transaction within a @synchronized(self) block.
// * If you update any account state in the database, reload the cache
//   immediately.
@interface TSAccountManager () <UIDatabaseSnapshotDelegate>

// This property should only be accessed while @synchronized on self.
//
// Generally, it will nil until loaded for the first time (while warming
// the caches) and non-nil after.
//
// There's an important exception: we discard (but don't reload) the cache
// when notified of a cross-process write.
@property (nonatomic, nullable) TSAccountState *cachedAccountState;

@end

#pragma mark -

@implementation TSAccountManager

@synthesize phoneNumberAwaitingVerification = _phoneNumberAwaitingVerification;
@synthesize uuidAwaitingVerification = _uuidAwaitingVerification;

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _keyValueStore = [[SDSKeyValueStore alloc] initWithCollection:TSAccountManager_UserAccountCollection];

    OWSSingletonAssert();

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        if (!CurrentAppContext().isMainApp) {
            [self.databaseStorage appendUIDatabaseSnapshotDelegate:self];
        }
    }];
    [AppReadiness runNowOrWhenAppDidBecomeReadyPolite:^{
        [self updateAccountAttributesIfNecessary];
    }];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityChanged)
                                                 name:SSKReachability.owsReachabilityDidChange
                                               object:nil];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (TSAccountManager *)shared
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);
    
    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark - Dependencies

- (TSNetworkManager *)networkManager
{
    OWSAssertDebug(SSKEnvironment.shared.networkManager);
    
    return SSKEnvironment.shared.networkManager;
}

- (id<ProfileManagerProtocol>)profileManager {
    OWSAssertDebug(SSKEnvironment.shared.profileManager);

    return SSKEnvironment.shared.profileManager;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (SSKSessionStore *)sessionStore
{
    return SSKEnvironment.shared.sessionStore;
}

- (id<OWSUDManager>)udManager
{
    return SSKEnvironment.shared.udManager;
}

#pragma mark -

- (void)warmCaches
{
    TSAccountState *accountState = [self loadAccountStateWithSneakyTransaction];

    [accountState log];
}

- (nullable NSString *)phoneNumberAwaitingVerification
{
    @synchronized(self) {
        return _phoneNumberAwaitingVerification;
    }
}

- (nullable NSUUID *)uuidAwaitingVerification
{
    @synchronized(self) {
        return _uuidAwaitingVerification;
    }
}

- (void)setPhoneNumberAwaitingVerification:(NSString *_Nullable)phoneNumberAwaitingVerification
{
    @synchronized(self) {
        _phoneNumberAwaitingVerification = phoneNumberAwaitingVerification;
    }

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:kNSNotificationName_LocalNumberDidChange
                                                             object:nil
                                                           userInfo:nil];
}

- (void)setUuidAwaitingVerification:(NSUUID *_Nullable)uuidAwaitingVerification
{
    @synchronized(self) {
        _uuidAwaitingVerification = uuidAwaitingVerification;
    }
}

- (OWSRegistrationState)registrationState
{
    if (!self.isRegistered) {
        return OWSRegistrationState_Unregistered;
    } else if (self.isDeregistered) {
        if (self.isReregistering) {
            return OWSRegistrationState_Reregistering;
        } else {
            return OWSRegistrationState_Deregistered;
        }
    } else {
        return OWSRegistrationState_Registered;
    }
}

- (TSAccountState *)loadAccountStateWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSLogVerbose(@"");

    // This method should only be called while @synchronized on self.
    TSAccountState *accountState = [[TSAccountState alloc] initWithTransaction:transaction
                                                                 keyValueStore:self.keyValueStore];
    self.cachedAccountState = accountState;
    return accountState;
}

- (TSAccountState *)getOrLoadAccountStateWithSneakyTransaction
{
    @synchronized (self) {
        if (self.cachedAccountState != nil) {
            return self.cachedAccountState;
        }
    }

    return [self loadAccountStateWithSneakyTransaction];
}

- (TSAccountState *)loadAccountStateWithSneakyTransaction
{
    // We avoid opening a transaction while @synchronized.
    __block TSAccountState *accountState;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        @synchronized(self) {
            accountState = [self loadAccountStateWithTransaction:transaction];
        }
    }];

    OWSAssertDebug(accountState != nil);
    return accountState;
}

- (TSAccountState *)getOrLoadAccountStateWithTransaction:(SDSAnyReadTransaction *)transaction
{
    @synchronized(self) {
        if (self.cachedAccountState != nil) {
            return self.cachedAccountState;
        }

        [self loadAccountStateWithTransaction:transaction];

        OWSAssertDebug(self.cachedAccountState != nil);

        return self.cachedAccountState;
    }
}

- (BOOL)isRegistered
{
    return [self getOrLoadAccountStateWithSneakyTransaction].isRegistered;
}

- (BOOL)isRegisteredWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.keyValueStore getString:TSAccountManager_RegisteredNumberKey transaction:transaction];
}

- (BOOL)isRegisteredAndReady
{
    return self.registrationState == OWSRegistrationState_Registered;
}

- (void)didRegister
{
    OWSLogInfo(@"");
    NSString *phoneNumber;
    NSUUID *uuid;
    @synchronized(self) {
        phoneNumber = self.phoneNumberAwaitingVerification;
        uuid = self.uuidAwaitingVerification;
    }

    if (!phoneNumber) {
        OWSFail(@"phoneNumber was unexpectedly nil");
    }

    if (!uuid) {
        OWSFail(@"uuid was unexpectedly nil");
    }

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self storeLocalNumber:phoneNumber uuid:uuid transaction:transaction];
    });

    [self postRegistrationStateDidChangeNotification];
}

- (void)recordUuidForLegacyUser:(NSUUID *)uuid
{
    OWSAssert(self.localUuid == nil);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        @synchronized(self) {
            [self.keyValueStore setString:uuid.UUIDString
                                      key:TSAccountManager_RegisteredUUIDKey
                              transaction:transaction];

            [self loadAccountStateWithTransaction:transaction];
        }
    });
}

+ (nullable NSString *)localNumber
{
    return [[self shared] localNumber];
}

- (nullable NSString *)localNumber
{
    return [self localNumberWithAccountState:[self getOrLoadAccountStateWithSneakyTransaction]];
}

- (nullable NSString *)localNumberWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self localNumberWithAccountState:[self getOrLoadAccountStateWithTransaction:transaction]];
}

- (nullable NSString *)localNumberWithAccountState:(TSAccountState *)accountState
{
    @synchronized(self)
    {
        NSString *awaitingVerif = self.phoneNumberAwaitingVerification;
        if (awaitingVerif) {
            return awaitingVerif;
        }
    }

    return accountState.localNumber;
}

- (nullable NSUUID *)localUuid
{
    return [self localUuidWithAccountState:[self getOrLoadAccountStateWithSneakyTransaction]];
}

- (nullable NSUUID *)localUuidWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self localUuidWithAccountState:[self getOrLoadAccountStateWithTransaction:transaction]];
}

- (nullable NSUUID *)localUuidWithAccountState:(TSAccountState *)accountState
{
    @synchronized(self) {
        NSUUID *awaitingVerif = self.uuidAwaitingVerification;
        if (awaitingVerif) {
            return awaitingVerif;
        }
    }

    return accountState.localUuid;
}

+ (nullable SignalServiceAddress *)localAddressWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.shared localAddressWithTransaction:transaction];
}

- (nullable SignalServiceAddress *)localAddressWithTransaction:(SDSAnyReadTransaction *)transaction
{
    TSAccountState *accountState = [self getOrLoadAccountStateWithTransaction:transaction];

    if (accountState.localUuid == nil && accountState.localNumber == nil) {
        return nil;
    } else {
        return [[SignalServiceAddress alloc] initWithUuidString:accountState.localUuid.UUIDString
                                                    phoneNumber:accountState.localNumber];
    }
}

+ (nullable SignalServiceAddress *)localAddress
{
    return [[self shared] localAddress];
}

- (nullable SignalServiceAddress *)localAddress
{
    // We extract uuid and local number from a single instance of accountState
    // to avoid races.
    TSAccountState *accountState = [self getOrLoadAccountStateWithSneakyTransaction];
    NSUUID *_Nullable localUuid = [self localUuidWithAccountState:accountState];
    NSString *_Nullable localNumber = [self localNumberWithAccountState:accountState];

    if (localUuid == nil && localNumber == nil) {
        return nil;
    } else {
        return [[SignalServiceAddress alloc] initWithUuidString:localUuid.UUIDString phoneNumber:localNumber];
    }
}

- (void)storeLocalNumber:(NSString *)localNumber
                    uuid:(NSUUID *)localUuid
             transaction:(SDSAnyWriteTransaction *)transaction
{
    @synchronized (self) {
        [self.keyValueStore setString:localNumber key:TSAccountManager_RegisteredNumberKey transaction:transaction];

        if (localUuid == nil) {
            OWSFail(@"Missing localUuid.");
        } else {
            [self.keyValueStore setString:localUuid.UUIDString
                                      key:TSAccountManager_RegisteredUUIDKey
                              transaction:transaction];
        }

        // Update the address cache mapping for the local user.
        [SSKEnvironment.shared.signalServiceAddressCache updateMappingWithUuid:localUuid phoneNumber:localNumber];

        [self.keyValueStore removeValueForKey:TSAccountManager_ReregisteringPhoneNumberKey transaction:transaction];

        [self loadAccountStateWithTransaction:transaction];

        self.phoneNumberAwaitingVerification = nil;
        self.uuidAwaitingVerification = nil;
    }
}

- (uint32_t)getOrGenerateRegistrationId
{
    __block uint32_t result;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        result = [self getOrGenerateRegistrationIdWithTransaction:transaction];
    });
    return result;
}

- (uint32_t)getOrGenerateRegistrationIdWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    // Unlike other methods in this class, there's no need for a `@synchronized` block
    // here, since we're already in a write transaction, and all writes occur on a serial queue.
    //
    // Since other code in this class which uses @synchronized(self) also needs to open write
    // transaction, using @synchronized(self) here, inside of a WriteTransaction risks deadlock.
    NSNumber *_Nullable storedId = [self.keyValueStore getObjectForKey:TSAccountManager_LocalRegistrationIdKey
                                                           transaction:transaction];

    uint32_t registrationID = storedId.unsignedIntValue;

    if (registrationID == 0) {
        registrationID = (uint32_t)arc4random_uniform(16380) + 1;
        OWSLogWarn(@"Generated a new registrationID: %u", registrationID);

        [self.keyValueStore setObject:[NSNumber numberWithUnsignedInteger:registrationID]
                                  key:TSAccountManager_LocalRegistrationIdKey
                          transaction:transaction];
    }
    return registrationID;
}

- (BOOL)isOnboarded
{
    return [self getOrLoadAccountStateWithSneakyTransaction].isOnboarded;
}

- (void)setIsOnboarded:(BOOL)isOnboarded transaction:(SDSAnyWriteTransaction *)transaction
{
    @synchronized(self) {
        [self.keyValueStore setBool:isOnboarded key:TSAccountManager_IsOnboardedKey transaction:transaction];
        [self loadAccountStateWithTransaction:transaction];
    }
}

- (BOOL)isDiscoverableByPhoneNumber
{
    return [self getOrLoadAccountStateWithSneakyTransaction].isDiscoverableByPhoneNumber;
}

- (BOOL)hasDefinedIsDiscoverableByPhoneNumber
{
    return [self getOrLoadAccountStateWithSneakyTransaction].hasDefinedIsDiscoverableByPhoneNumber;
}

- (void)setIsDiscoverableByPhoneNumber:(BOOL)isDiscoverableByPhoneNumber
                  updateStorageService:(BOOL)updateStorageService
                           transaction:(SDSAnyWriteTransaction *)transaction
{
    if (!SSKFeatureFlags.phoneNumberDiscoverability) {
        return;
    }

    @synchronized(self) {
        [self.keyValueStore setBool:isDiscoverableByPhoneNumber
                                key:TSAccountManager_IsDiscoverableByPhoneNumber
                        transaction:transaction];
        [self loadAccountStateWithTransaction:transaction];
    }

    [transaction addAsyncCompletion:^{
        [self updateAccountAttributes];

        if (updateStorageService) {
            [SSKEnvironment.shared.storageServiceManager recordPendingLocalAccountUpdates];
        }
    }];
}

#pragma mark - Network Requests

- (void)registerForPushNotificationsWithPushToken:(NSString *)pushToken
                                        voipToken:(NSString *)voipToken
                                          success:(void (^)(void))successHandler
                                          failure:(void (^)(NSError *))failureHandler
{
    [self registerForPushNotificationsWithPushToken:pushToken
                                          voipToken:voipToken
                                            success:successHandler
                                            failure:failureHandler
                                   remainingRetries:3];
}

- (void)registerForPushNotificationsWithPushToken:(NSString *)pushToken
                                        voipToken:(NSString *)voipToken
                                          success:(void (^)(void))successHandler
                                          failure:(void (^)(NSError *))failureHandler
                                 remainingRetries:(int)remainingRetries
{
    TSRequest *request =
        [OWSRequestFactory registerForPushRequestWithPushIdentifier:pushToken voipIdentifier:voipToken];
    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            successHandler();
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (remainingRetries > 0) {
                [self registerForPushNotificationsWithPushToken:pushToken
                                                      voipToken:voipToken
                                                        success:successHandler
                                                        failure:failureHandler
                                               remainingRetries:remainingRetries - 1];
            } else {
                if (!IsNetworkConnectivityFailure(error)) {
                    OWSProdError([OWSAnalyticsEvents accountsErrorRegisterPushTokensFailed]);
                }
                failureHandler(error);
            }
        }];
}

- (void)verifyAccountWithRequest:(TSRequest *)request
                         success:(void (^)(_Nullable id responseObject))successBlock
                         failure:(void (^)(NSError *error))failureBlock
{
    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            long statuscode = response.statusCode;

            switch (statuscode) {
                case 200:
                case 204: {
                    OWSLogInfo(@"Verification code accepted.");
                    successBlock(responseObject);
                    break;
                }
                default: {
                    OWSLogError(@"Unexpected status while verifying code: %ld", statuscode);
                    NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                    failureBlock(error);
                    break;
                }
            }
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (IsNetworkConnectivityFailure(error)) {
                OWSLogWarn(@"network error: %@", error.debugDescription);
            } else {
                OWSLogError(@"non-network error: %@", error.debugDescription);
            }
            OWSAssertDebug([error.domain isEqualToString:TSNetworkManagerErrorDomain]);

            switch (error.code) {
                case 403: {
                    NSError *userError = OWSErrorWithCodeDescription(OWSErrorCodeUserError,
                        NSLocalizedString(@"REGISTRATION_VERIFICATION_FAILED_WRONG_CODE_DESCRIPTION",
                            "Error message indicating that registration failed due to a missing or incorrect "
                            "verification code."));
                    failureBlock(userError);
                    break;
                }
                case 409: {
                    NSError *userError = OWSErrorWithCodeDescription(OWSErrorCodeRegistrationTransferAvailable,
                        @"There was an account previously registered with this number that is available for transfer.");
                    failureBlock(userError);
                    break;
                }
                case 413: {
                    // In the case of the "rate limiting" error, we want to show the
                    // "recovery suggestion", not the error's "description."
                    NSError *userError
                        = OWSErrorWithCodeDescription(OWSErrorCodeUserError, error.localizedRecoverySuggestion);
                    failureBlock(userError);
                    break;
                }
                case 423: {
                    NSString *localizedMessage = NSLocalizedString(@"REGISTRATION_VERIFICATION_FAILED_WRONG_PIN",
                        "Error message indicating that registration failed due to a missing or incorrect 2FA PIN.");
                    OWSLogError(@"2FA PIN required: %ld", (long)error.code);

                    NSError *userError = OWSErrorWithCodeDescription(OWSErrorCodeRegistrationMissing2FAPIN, localizedMessage);

                    NSData *responseData = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
                    if (responseData == nil) {
                        OWSFailDebug(@"Response data is unexpectedly nil");
                        return failureBlock(OWSErrorMakeUnableToProcessServerResponseError());
                    }

                    NSError *error;
                    NSDictionary<NSString *, id> *_Nullable responseDict =
                        [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&error];
                    if (![responseDict isKindOfClass:[NSDictionary class]] || error != nil) {
                        OWSFailDebug(@"Failed to parse 2fa required json");
                        return failureBlock(OWSErrorMakeUnableToProcessServerResponseError());
                    }

                    // Check if we received KBS credentials, if so pass them on.
                    // This should only ever be returned if the user was using registration lock v2
                    NSDictionary *_Nullable backupCredentials = responseDict[@"backupCredentials"];
                    if ([backupCredentials isKindOfClass:[NSDictionary class]]) {
                        RemoteAttestationAuth *_Nullable auth = [RemoteAttestation parseAuthParams:backupCredentials];
                        if (!auth) {
                            OWSFailDebug(@"remote attestation auth could not be parsed: %@", responseDict);
                            return failureBlock(OWSErrorMakeUnableToProcessServerResponseError());
                        }

                        userError = OWSErrorWithUserInfo(OWSErrorCodeRegistrationMissing2FAPIN,
                                                         @{
                                                           NSLocalizedDescriptionKey: localizedMessage,
                                                           TSRemoteAttestationAuthErrorKey: auth
                                                         });
                    }

                    failureBlock(userError);
                    break;
                }
                default: {
                    OWSLogError(@"verifying code failed with unknown error: %@", error);
                    failureBlock(error);
                    break;
                }
            }
        }];
}

#pragma mark Server keying material

// NOTE: We no longer set this for new accounts.
- (nullable NSString *)storedSignalingKey
{
    return [self getOrLoadAccountStateWithSneakyTransaction].serverSignalingKey;
}

- (nullable NSString *)storedServerAuthToken
{
    return [self getOrLoadAccountStateWithSneakyTransaction].serverAuthToken;
}

- (nullable NSString *)storedDeviceName
{
    return [self getOrLoadAccountStateWithSneakyTransaction].deviceName;
}

- (UInt32)storedDeviceId
{
    return [self getOrLoadAccountStateWithSneakyTransaction].deviceId;
}

- (UInt32)storedDeviceIdWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self getOrLoadAccountStateWithTransaction:transaction].deviceId;
}

- (void)setStoredServerAuthToken:(NSString *)authToken
                        deviceId:(UInt32)deviceId
                     transaction:(SDSAnyWriteTransaction *)transaction
{
    @synchronized(self) {
        [self.keyValueStore setString:authToken key:TSAccountManager_ServerAuthToken transaction:transaction];
        [self.keyValueStore setUInt32:deviceId key:TSAccountManager_DeviceId transaction:transaction];

        [self loadAccountStateWithTransaction:transaction];
    }
}

- (void)setStoredDeviceName:(NSString *)deviceName transaction:(SDSAnyWriteTransaction *)transaction
{
    @synchronized(self) {
        [self.keyValueStore setString:deviceName key:TSAccountManager_DeviceName transaction:transaction];

        [self loadAccountStateWithTransaction:transaction];
    }
}

+ (void)unregisterTextSecureWithSuccess:(void (^)(void))success failure:(void (^)(NSError *error))failureBlock
{
    TSRequest *request = [OWSRequestFactory unregisterAccountRequest];
    [[TSNetworkManager shared] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            OWSLogInfo(@"Successfully unregistered");
            success();

            // This is called from `[AppSettingsViewController proceedToUnregistration]` whose
            // success handler calls `[Environment resetAppData]`.
            // This method, after calling that success handler, fires
            // `RegistrationStateDidChangeNotification` which is only safe to fire after
            // the data store is reset.

            [self.shared postRegistrationStateDidChangeNotification];
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNetworkConnectivityFailure(error)) {
                OWSProdError([OWSAnalyticsEvents accountsErrorUnregisterAccountRequestFailed]);
            }
            OWSLogError(@"Failed to unregister with error: %@", error);
            failureBlock(error);
        }];
}

#pragma mark - De-Registration

- (BOOL)isDeregistered
{
    TSAccountState *state = [self getOrLoadAccountStateWithSneakyTransaction];
    // An in progress transfer is treated as being deregistered.
    return state.isTransferInProgress || state.wasTransferred || state.isDeregistered;
}

- (void)setIsDeregistered:(BOOL)isDeregistered
{
    if ([self getOrLoadAccountStateWithSneakyTransaction].isDeregistered == isDeregistered) {
        // Skip redundant write.
        return;
    }

    OWSLogWarn(@"Updating isDeregistered: %d", isDeregistered);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        @synchronized(self) {
            [self.keyValueStore setObject:@(isDeregistered)
                                      key:TSAccountManager_IsDeregisteredKey
                              transaction:transaction];

            [self loadAccountStateWithTransaction:transaction];
        }
    });

    [self postRegistrationStateDidChangeNotification];
}

#pragma mark - Re-registration

- (BOOL)resetForReregistration
{
    NSString *_Nullable localNumber = [self getOrLoadAccountStateWithSneakyTransaction].localNumber;
    if (!localNumber) {
        OWSFailDebug(@"can't re-register without valid local number.");
        return NO;
    }

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        @synchronized(self) {
            self.phoneNumberAwaitingVerification = nil;
            self.uuidAwaitingVerification = nil;

            [self.keyValueStore removeAllWithTransaction:transaction];

            [self.sessionStore resetSessionStore:transaction];

            [self.udManager removeSenderCertificatesWithTransaction:transaction];

            [self.keyValueStore setObject:localNumber
                                      key:TSAccountManager_ReregisteringPhoneNumberKey
                              transaction:transaction];

            [self.keyValueStore setBool:NO key:TSAccountManager_IsOnboardedKey transaction:transaction];

            [self loadAccountStateWithTransaction:transaction];

            [OWSKeyBackupService clearKeysWithTransaction:transaction];
            [OWS2FAManager.shared setPinCode:nil transaction:transaction];
        }
    });

    [self postRegistrationStateDidChangeNotification];

    return YES;
}

- (nullable NSString *)reregistrationPhoneNumber
{
    OWSAssertDebug([self isReregistering]);

    return [self getOrLoadAccountStateWithSneakyTransaction].reregistrationPhoneNumber;
}

- (BOOL)isReregistering
{
    return [self getOrLoadAccountStateWithSneakyTransaction].isReregistering;
}

- (BOOL)isTransferInProgress
{
    return [self getOrLoadAccountStateWithSneakyTransaction].isTransferInProgress;
}

- (void)setIsTransferInProgress:(BOOL)transferInProgress
{
    if (transferInProgress == self.isTransferInProgress) {
        return;
    }

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        @synchronized(self) {
            [self.keyValueStore setObject:@(transferInProgress)
                                      key:TSAccountManager_IsTransferInProgressKey
                              transaction:transaction];

            [self loadAccountStateWithTransaction:transaction];
        }
    });

    [self postRegistrationStateDidChangeNotification];
}

- (BOOL)wasTransferred
{
    return [self getOrLoadAccountStateWithSneakyTransaction].wasTransferred;
}

- (void)setWasTransferred:(BOOL)wasTransferred
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        @synchronized(self) {
            [self.keyValueStore setObject:@(wasTransferred)
                                      key:TSAccountManager_WasTransferredKey
                              transaction:transaction];

            [self loadAccountStateWithTransaction:transaction];
        }
    });

    [self postRegistrationStateDidChangeNotification];
}

- (BOOL)hasPendingBackupRestoreDecision
{
    __block BOOL result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyValueStore getBool:TSAccountManager_HasPendingRestoreDecisionKey
                                defaultValue:NO
                                 transaction:transaction];
    }];
    return result;
}

- (void)setHasPendingBackupRestoreDecision:(BOOL)value
{
    OWSLogInfo(@"%d", value);
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setBool:value key:TSAccountManager_HasPendingRestoreDecisionKey transaction:transaction];
    });
    [self postRegistrationStateDidChangeNotification];
}

- (BOOL)isManualMessageFetchEnabled
{
    __block BOOL result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result =
            [self.keyValueStore getBool:TSAccountManager_ManualMessageFetchKey defaultValue:NO transaction:transaction];
    }];
    return result;
}

- (void)setIsManualMessageFetchEnabled:(BOOL)value
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setBool:value key:TSAccountManager_ManualMessageFetchKey transaction:transaction];
    });
}

- (void)registerForTestsWithLocalNumber:(NSString *)localNumber uuid:(NSUUID *)uuid
{
    OWSAssertDebug(
        SSKFeatureFlags.storageMode == StorageModeYdbTests || SSKFeatureFlags.storageMode == StorageModeGrdbTests);
    OWSAssertDebug(CurrentAppContext().isRunningTests);
    OWSAssertDebug(localNumber.length > 0);
    OWSAssertDebug(uuid != nil);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self storeLocalNumber:localNumber uuid:uuid transaction:transaction];
    });
}

- (void)reachabilityChanged {
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppDidBecomeReadyPolite:^{
        [self updateAccountAttributesIfNecessary];
    }];
}

#pragma mark - Notifications

- (void)postRegistrationStateDidChangeNotification
{
    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:NSNotificationNameRegistrationStateDidChange
                                                             object:nil
                                                           userInfo:nil];
}

#pragma mark - UIDatabaseSnapshotDelegate

- (void)uiDatabaseSnapshotWillUpdate
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(AppReadiness.isAppReady);
}

- (void)uiDatabaseSnapshotDidUpdateWithDatabaseChanges:(id<UIDatabaseChanges>)databaseChanges
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(AppReadiness.isAppReady);

    // Do nothing.
}

- (void)uiDatabaseSnapshotDidUpdateExternally
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(AppReadiness.isAppReady);

    OWSLogVerbose(@"");

    // Any database write by the main app might reflect a deregistration,
    // so clear the cached "is registered" state.  This will significantly
    // erode the value of this cache in the SAE.
    [self loadAccountStateWithSneakyTransaction];
}

- (void)uiDatabaseSnapshotDidReset
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(AppReadiness.isAppReady);

    // Do nothing.
}

@end

NS_ASSUME_NONNULL_END
