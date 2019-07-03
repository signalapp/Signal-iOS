//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSAccountManager.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "NSNotificationCenter+OWS.h"
#import "NSURLSessionDataTask+StatusCode.h"
#import "OWSError.h"
#import "OWSRequestFactory.h"
#import "ProfileManagerProtocol.h"
#import "RemoteAttestation.h"
#import "SSKEnvironment.h"
#import "SSKSessionStore.h"
#import "TSNetworkManager.h"
#import "TSPreKeyManager.h"
#import <PromiseKit/AnyPromise.h>
#import <Reachability/Reachability.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSRegistrationErrorDomain = @"TSRegistrationErrorDomain";
NSString *const TSRegistrationErrorUserInfoHTTPStatus = @"TSHTTPStatus";
NSString *const RegistrationStateDidChangeNotification = @"RegistrationStateDidChangeNotification";
NSString *const TSRemoteAttestationAuthErrorKey = @"TSRemoteAttestationAuth";
NSString *const kNSNotificationName_LocalNumberDidChange = @"kNSNotificationName_LocalNumberDidChange";

NSString *const TSAccountManager_RegisteredNumberKey = @"TSStorageRegisteredNumberKey";
NSString *const TSAccountManager_RegisteredUUIDKey = @"TSStorageRegisteredUUIDKey";
NSString *const TSAccountManager_IsDeregisteredKey = @"TSAccountManager_IsDeregisteredKey";
NSString *const TSAccountManager_ReregisteringPhoneNumberKey = @"TSAccountManager_ReregisteringPhoneNumberKey";
NSString *const TSAccountManager_LocalRegistrationIdKey = @"TSStorageLocalRegistrationId";
NSString *const TSAccountManager_HasPendingRestoreDecisionKey = @"TSAccountManager_HasPendingRestoreDecisionKey";

NSString *const TSAccountManager_UserAccountCollection = @"TSStorageUserAccountCollection";
NSString *const TSAccountManager_ServerAuthToken = @"TSStorageServerAuthToken";
NSString *const TSAccountManager_ServerSignalingKey = @"TSStorageServerSignalingKey";
NSString *const TSAccountManager_ManualMessageFetchKey = @"TSAccountManager_ManualMessageFetchKey";
NSString *const TSAccountManager_NeedsAccountAttributesUpdateKey = @"TSAccountManager_NeedsAccountAttributesUpdateKey";

@interface TSAccountManager ()

@property (nonatomic, nullable) NSString *cachedLocalNumber;
@property (nonatomic, nullable) NSUUID *cachedUuid;

@property (nonatomic, nullable) NSNumber *cachedIsDeregistered;

@property (nonatomic) Reachability *reachability;

@end

#pragma mark -

@implementation TSAccountManager

@synthesize isRegistered = _isRegistered;

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _keyValueStore = [[SDSKeyValueStore alloc] initWithCollection:TSAccountManager_UserAccountCollection];
    self.reachability = [Reachability reachabilityForInternetConnection];

    OWSSingletonAssert();

    if (!CurrentAppContext().isMainApp) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(yapDatabaseModifiedExternally:)
                                                     name:YapDatabaseModifiedExternallyNotification
                                                   object:nil];
    }

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [[self updateAccountAttributesIfNecessary] retainUntilComplete];
    }];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityChanged)
                                                 name:kReachabilityChangedNotification
                                               object:nil];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (instancetype)sharedInstance
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

- (OWSPrimaryStorage *)primaryStorage
{
    OWSAssertDebug(SSKEnvironment.shared.primaryStorage);

    return SSKEnvironment.shared.primaryStorage;
}

#pragma mark -

- (void)setPhoneNumberAwaitingVerification:(NSString *_Nullable)phoneNumberAwaitingVerification
{
    _phoneNumberAwaitingVerification = phoneNumberAwaitingVerification;

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:kNSNotificationName_LocalNumberDidChange
                                                             object:nil
                                                           userInfo:nil];
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
    } else if (self.isDeregistered) {
        return OWSRegistrationState_PendingBackupRestore;
    } else {
        return OWSRegistrationState_Registered;
    }
}

- (BOOL)isRegistered
{
    @synchronized (self) {
        if (_isRegistered) {
            return YES;
        } else {
            // Cache this once it's true since it's called alot, involves a dbLookup, and once set - it doesn't change.
            _isRegistered = [self storedLocalNumber] != nil;
        }
        return _isRegistered;
    }
}

- (BOOL)isRegisteredAndReady
{
    return self.registrationState == OWSRegistrationState_Registered;
}

- (void)didRegister
{
    OWSLogInfo(@"didRegister");
    NSString *phoneNumber = self.phoneNumberAwaitingVerification;

    if (!phoneNumber) {
        OWSFail(@"phoneNumber was unexpectedly nil");
    }

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        // UUID TODO: pass in uuid returned from registration verification
        [self storeLocalNumber:phoneNumber uuid:nil transaction:transaction];
    }];

    // Warm these cached values.
    [self isRegistered];
    [self localNumber];
    [self isDeregistered];

    [self postRegistrationStateDidChangeNotification];
}

+ (nullable NSString *)localNumber
{
    return [[self sharedInstance] localNumber];
}

- (nullable NSString *)localNumber
{
    NSString *awaitingVerif = self.phoneNumberAwaitingVerification;
    if (awaitingVerif) {
        return awaitingVerif;
    }

    // Cache this since we access this a lot, and once set it will not change.
    @synchronized(self)
    {
        if (self.cachedLocalNumber == nil) {
            self.cachedLocalNumber = self.storedLocalNumber;
        }
    }

    return self.cachedLocalNumber;
}

- (nullable NSString *)storedLocalNumber
{
    @synchronized (self) {
        __block NSString *_Nullable result;

        // GRDB TODO: Until GRDB migration is complete, we need to load this from YDB,
        //
        // * YAPDBJobRecordFinder uses a secondary index.
        // * Yaps views and indices enumerate all (per whitelist or blacklist) entities when building or updating the
        //   index. Views and indices can be built or re-built on launch.
        // * These views and indices are built before migrations are run and "database is ready".
        // * MessageSenderJobQueue uses SSKMessageSenderJobRecord whose invisibleMessage is an TSOutgoingMessage.
        //   Therefore (re-)building YAPDBJobRecordFinder's index can deserialize outgoing sync messages.
        // * OWSOutgoingSyncMessage extends TSOutgoingMessage whose deserialization initializer initWithCoder uses
        //   TSAccountManager.localNumber.
        // * TSAccountManager.localNumber is persisted in the database.
        // * When we load TSAccountManager.localNumber we use the "current" database which might be GRDB. GRDB might not
        //   be populated because the migration hasn't occurred yet.
        //
        // GRDB TODO: GRDB_MIGRATION_COMPLETE might eventually be replaced by a flag set at runtime.
#ifdef GRDB_MIGRATION_COMPLETE
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            result = [self.keyValueStore getString:TSAccountManager_RegisteredNumberKey transaction:transaction];
        }];
#else
        [self.primaryStorage.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            result =
                [self.keyValueStore getString:TSAccountManager_RegisteredNumberKey transaction:transaction.asAnyRead];
        }];
#endif
        return result;
    }
}

- (nullable NSUUID *)uuid
{
    // Cache this since we access this a lot, and once set it will not change.
    @synchronized(self) {
        if (self.cachedUuid == nil) {
            self.cachedUuid = self.storedUuid;
        }

        return self.cachedUuid;
    }
}

- (nullable NSUUID *)storedUuid
{
    @synchronized(self) {
        __block NSUUID *_Nullable result;
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            NSString *_Nullable storedString = [self.keyValueStore getString:TSAccountManager_RegisteredUUIDKey
                                                                 transaction:transaction];

            if (storedString != nil) {
                result = [[NSUUID alloc] initWithUUIDString:storedString];
                OWSAssert(result);
            }
        }];
        return result;
    }
}

- (nullable SignalServiceAddress *)storedOrCachedLocalAddress:(SDSAnyReadTransaction *)transaction
{
    @synchronized(self) {
        NSString *_Nullable localNumber = self.cachedLocalNumber;
        NSString *_Nullable uuidString = self.cachedUuid.UUIDString;

        if (localNumber == nil) {
            localNumber = [self.keyValueStore getString:TSAccountManager_RegisteredNumberKey transaction:transaction];
        }

        if (uuidString == nil) {
            uuidString = [self.keyValueStore getString:TSAccountManager_RegisteredUUIDKey transaction:transaction];
        }

        if (uuidString == nil && localNumber == nil) {
            return nil;
        }

        return [[SignalServiceAddress alloc] initWithUuidString:uuidString phoneNumber:localNumber];
    }
}

- (nullable SignalServiceAddress *)localAddress
{
    if (!self.uuid && !self.localNumber) {
        return nil;
    }

    return [[SignalServiceAddress alloc] initWithUuidString:self.uuid.UUIDString phoneNumber:self.localNumber];
}

// TODO UUID: make uuid non-nullable when enabling SSKFeatureFlags.allowUUIDOnlyContacts in production
- (void)storeLocalNumber:(NSString *)localNumber
                    uuid:(nullable NSUUID *)uuid
             transaction:(SDSAnyWriteTransaction *)transaction
{
    @synchronized (self) {
        [self.keyValueStore setString:localNumber key:TSAccountManager_RegisteredNumberKey transaction:transaction];

        if (uuid == nil) {
            OWSAssert(!SSKFeatureFlags.allowUUIDOnlyContacts);
        } else {
            [self.keyValueStore setString:uuid.UUIDString
                                      key:TSAccountManager_RegisteredUUIDKey
                              transaction:transaction];
        }

        [self.keyValueStore removeValueForKey:TSAccountManager_ReregisteringPhoneNumberKey transaction:transaction];

        self.phoneNumberAwaitingVerification = nil;
        self.cachedLocalNumber = localNumber;
    }
}


- (uint32_t)getOrGenerateRegistrationId
{
    __block uint32_t result;
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        result = [self getOrGenerateRegistrationIdWithTransaction:transaction];
    }];
    return result;
}

- (uint32_t)getOrGenerateRegistrationIdWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    // Unlike other methods in this class, there's no need for a `@synchronized` block
    // here, since we're already in a write transaction, and all writes occur on a serial queue.
    //
    // Since other code in this class which uses @synchronized(self) also needs to open write
    // transaction, using @synchronized(self) here, inside of a WriteTransaction risks deadlock.
    NSNumber *_Nullable storedId =
        [self.keyValueStore getObject:TSAccountManager_LocalRegistrationIdKey transaction:transaction];

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
                if (!IsNSErrorNetworkFailure(error)) {
                    OWSProdError([OWSAnalyticsEvents accountsErrorRegisterPushTokensFailed]);
                }
                failureHandler(error);
            }
        }];
}

- (void)verifyAccountWithCode:(NSString *)verificationCode
                          pin:(nullable NSString *)pin
                      success:(void (^)(void))successBlock
                      failure:(void (^)(NSError *error))failureBlock
{
    NSString *authToken = [[self class] generateNewAccountAuthenticationToken];
    NSString *phoneNumber = self.phoneNumberAwaitingVerification;

    OWSAssertDebug(authToken);
    OWSAssertDebug(phoneNumber);

    TSRequest *request = [OWSRequestFactory verifyCodeRequestWithVerificationCode:verificationCode
                                                                        forNumber:phoneNumber
                                                                              pin:pin
                                                                          authKey:authToken];

    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            long statuscode = response.statusCode;

            switch (statuscode) {
                case 200:
                case 204: {
                    OWSLogInfo(@"Verification code accepted.");

                    [self setStoredServerAuthToken:authToken];

                    [[[SignalServiceRestClient new] updateAccountAttributesObjC]
                            .thenInBackground(^{
                                return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
                                    [TSPreKeyManager
                                        createPreKeysWithSuccess:^{
                                            resolve(@(1));
                                        }
                                        failure:^(NSError *error) {
                                            resolve(error);
                                        }];
                                }];
                            })
                            .then(^{
                                [self.profileManager fetchLocalUsersProfile];
                            })
                            .then(^{
                                successBlock();
                            })
                            .catchInBackground(^(NSError *error) {
                                OWSLogError(@"Error: %@", error);
                                failureBlock(error);
                            }) retainUntilComplete];

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
            if (!IsNSErrorNetworkFailure(error)) {
                OWSProdError([OWSAnalyticsEvents accountsErrorVerifyAccountRequestFailed]);
            }
            OWSAssertDebug([error.domain isEqualToString:TSNetworkManagerErrorDomain]);

            OWSLogWarn(@"Error verifying code: %@", error.debugDescription);

            switch (error.code) {
                case 403: {
                    NSError *userError = OWSErrorWithCodeDescription(OWSErrorCodeUserError,
                        NSLocalizedString(@"REGISTRATION_VERIFICATION_FAILED_WRONG_CODE_DESCRIPTION",
                            "Error message indicating that registration failed due to a missing or incorrect "
                            "verification code."));
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
                    NSDictionary *_Nullable storageCredentials = responseDict[@"storageCredentials"];
                    if ([storageCredentials isKindOfClass:[NSDictionary class]]) {
                        RemoteAttestationAuth *_Nullable auth = [RemoteAttestation parseAuthParams:storageCredentials];
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

+ (NSString *)generateNewAccountAuthenticationToken {
    NSData *authToken = [Randomness generateRandomBytes:16];
    NSString *authTokenPrint = [[NSData dataWithData:authToken] hexadecimalString];
    return authTokenPrint;
}

- (nullable NSString *)storedSignalingKey
{
    __block NSString *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyValueStore getString:TSAccountManager_ServerSignalingKey transaction:transaction];
    }];
    return result;
}

- (nullable NSString *)storedServerAuthToken
{
    __block NSString *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyValueStore getString:TSAccountManager_ServerAuthToken transaction:transaction];
    }];
    return result;
}

- (void)setStoredServerAuthToken:(NSString *)authToken
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setString:authToken key:TSAccountManager_ServerAuthToken transaction:transaction];
    }];
}

+ (void)unregisterTextSecureWithSuccess:(void (^)(void))success failure:(void (^)(NSError *error))failureBlock
{
    TSRequest *request = [OWSRequestFactory unregisterAccountRequest];
    [[TSNetworkManager sharedManager] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            OWSLogInfo(@"Successfully unregistered");
            success();

            // This is called from `[AppSettingsViewController proceedToUnregistration]` whose
            // success handler calls `[Environment resetAppData]`.
            // This method, after calling that success handler, fires
            // `RegistrationStateDidChangeNotification` which is only safe to fire after
            // the data store is reset.

            [self.sharedInstance postRegistrationStateDidChangeNotification];
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNSErrorNetworkFailure(error)) {
                OWSProdError([OWSAnalyticsEvents accountsErrorUnregisterAccountRequestFailed]);
            }
            OWSLogError(@"Failed to unregister with error: %@", error);
            failureBlock(error);
        }];
}

- (void)yapDatabaseModifiedExternally:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    OWSLogVerbose(@"");

    // Any database write by the main app might reflect a deregistration,
    // so clear the cached "is registered" state.  This will significantly
    // erode the value of this cache in the SAE.
    @synchronized(self)
    {
        _isRegistered = NO;
    }
}

#pragma mark - De-Registration

- (BOOL)isDeregistered
{
    // Cache this since we access this a lot, and once set it will not change.
    @synchronized(self) {
        if (self.cachedIsDeregistered == nil) {
            [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
                self.cachedIsDeregistered = @([self.keyValueStore getBool:TSAccountManager_IsDeregisteredKey
                                                             defaultValue:NO
                                                              transaction:transaction]);
            }];
        }

        OWSAssertDebug(self.cachedIsDeregistered);
        return self.cachedIsDeregistered.boolValue;
    }
}

- (void)setIsDeregistered:(BOOL)isDeregistered
{
    @synchronized(self) {
        if (self.cachedIsDeregistered && self.cachedIsDeregistered.boolValue == isDeregistered) {
            return;
        }

        OWSLogWarn(@"isDeregistered: %d", isDeregistered);

        self.cachedIsDeregistered = @(isDeregistered);
    }

    [self.databaseStorage
        asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
            [self.keyValueStore setObject:@(isDeregistered)
                                      key:TSAccountManager_IsDeregisteredKey
                              transaction:transaction];
        }
        completion:^{
            [self postRegistrationStateDidChangeNotification];
        }];
}

#pragma mark - Re-registration

- (BOOL)resetForReregistration
{
    @synchronized(self) {
        NSString *_Nullable localNumber = self.localNumber;
        if (!localNumber) {
            OWSFailDebug(@"can't re-register without valid local number.");
            return NO;
        }

        _isRegistered = NO;
        _cachedLocalNumber = nil;
        _phoneNumberAwaitingVerification = nil;
        _cachedIsDeregistered = nil;
        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            [self.keyValueStore removeAllWithTransaction:transaction];

            [self.sessionStore resetSessionStore:transaction];

            [self.keyValueStore setObject:localNumber
                                      key:TSAccountManager_ReregisteringPhoneNumberKey
                              transaction:transaction];
        }];

        [self postRegistrationStateDidChangeNotification];

        return YES;
    }
}

- (nullable NSString *)reregistrationPhoneNumber
{
    OWSAssertDebug([self isReregistering]);

    __block NSString *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyValueStore getString:TSAccountManager_ReregisteringPhoneNumberKey transaction:transaction];
        OWSAssertDebug(result);
    }];
    return result;
}

- (BOOL)isReregistering
{
    __block NSString *_Nullable reregistrationPhoneNumber;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        reregistrationPhoneNumber =
            [self.keyValueStore getString:TSAccountManager_ReregisteringPhoneNumberKey transaction:transaction];
    }];

    return nil != reregistrationPhoneNumber;
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
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setBool:value key:TSAccountManager_HasPendingRestoreDecisionKey transaction:transaction];
    }];
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
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setBool:value key:TSAccountManager_ManualMessageFetchKey transaction:transaction];
    }];
}

- (void)registerForTestsWithLocalNumber:(NSString *)localNumber uuid:(NSUUID *)uuid
{
    OWSAssertDebug(localNumber.length > 0);
    OWSAssertDebug(uuid != nil);

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self storeLocalNumber:localNumber uuid:uuid transaction:transaction];
    }];
    if (SSKFeatureFlags.useGRDB) {
        // Redundantly store in yap db as well - this works around another work around, which
        // insists on reading account registration state from YapDB.
        [self.primaryStorage.dbReadWriteConnection
            readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                [self storeLocalNumber:localNumber uuid:uuid transaction:transaction.asAnyWrite];
            }];
    }
}


#pragma mark - Account Attributes

- (AnyPromise *)updateAccountAttributes
{
    // Enqueue a "account attribute update", recording the "request time".
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setObject:[NSDate new]
                                  key:TSAccountManager_NeedsAccountAttributesUpdateKey
                          transaction:transaction];
    }];

    return [self updateAccountAttributesIfNecessary];
}

- (AnyPromise *)updateAccountAttributesIfNecessary {
    if (!self.isRegistered) {
        return [AnyPromise promiseWithValue:@(1)];
    }

    __block NSDate *_Nullable updateRequestDate;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        updateRequestDate =
            [self.keyValueStore getObject:TSAccountManager_NeedsAccountAttributesUpdateKey transaction:transaction];
    }];

    if (!updateRequestDate) {
        return [AnyPromise promiseWithValue:@(1)];
    }
    AnyPromise *promise = [self performUpdateAccountAttributes];
    promise = promise.thenInBackground(^(id value) {
        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            // Clear the update request unless a new update has been requested
            // while this update was in flight.
            NSDate *_Nullable latestUpdateRequestDate =
                [self.keyValueStore getObject:TSAccountManager_NeedsAccountAttributesUpdateKey transaction:transaction];

            if (latestUpdateRequestDate && [latestUpdateRequestDate isEqual:updateRequestDate]) {
                [self.keyValueStore removeValueForKey:TSAccountManager_NeedsAccountAttributesUpdateKey
                                          transaction:transaction];
            }
        }];
    });
    return promise;
}

- (AnyPromise *)performUpdateAccountAttributes
{
    AnyPromise *promise = [[SignalServiceRestClient new] updateAccountAttributesObjC];
    promise = promise.then(^(id value) {
        // Fetch the local profile, as we may have changed its
        // account attributes.  Specifically, we need to determine
        // if all devices for our account now support UD for sync
        // messages.
        [self.profileManager fetchLocalUsersProfile];
    });
    [promise retainUntilComplete];
    return promise;
}

- (void)reachabilityChanged {
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [[self updateAccountAttributesIfNecessary] retainUntilComplete];
    }];
}

#pragma mark - Notifications

- (void)postRegistrationStateDidChangeNotification
{
    OWSAssertIsOnMainThread();

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:RegistrationStateDidChangeNotification
                                                             object:nil
                                                           userInfo:nil];
}

@end

NS_ASSUME_NONNULL_END
