//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSAccountManager.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "NSNotificationCenter+OWS.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "YapDatabaseConnection+OWS.h"
#import "YapDatabaseTransaction+OWS.h"
#import <PromiseKit/AnyPromise.h>
#import <Reachability/Reachability.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSRegistrationErrorDomain = @"TSRegistrationErrorDomain";
NSString *const TSRegistrationErrorUserInfoHTTPStatus = @"TSHTTPStatus";
NSString *const RegistrationStateDidChangeNotification = @"RegistrationStateDidChangeNotification";
NSString *const kNSNotificationName_LocalNumberDidChange = @"kNSNotificationName_LocalNumberDidChange";

NSString *const TSAccountManager_RegisteredNumberKey = @"TSStorageRegisteredNumberKey";
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

@property (atomic, readonly) BOOL isRegistered;

@property (nonatomic, nullable) NSString *cachedLocalNumber;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@property (nonatomic, nullable) NSNumber *cachedIsDeregistered;

@property (nonatomic) Reachability *reachability;

@end

#pragma mark -

@implementation TSAccountManager

@synthesize isRegistered = _isRegistered;

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];
    if (!self) {
        return self;
    }

    _dbConnection = [primaryStorage newDatabaseConnection];
    self.reachability = [Reachability reachabilityForInternetConnection];

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
    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark - Dependencies

- (id<ProfileManagerProtocol>)profileManager {
    return SSKEnvironment.shared.profileManager;
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
    NSString *phoneNumber = self.phoneNumberAwaitingVerification;

    [self storeLocalNumber:phoneNumber];

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
        return [self.dbConnection stringForKey:TSAccountManager_RegisteredNumberKey
                                  inCollection:TSAccountManager_UserAccountCollection];
    }
}

- (nullable NSString *)storedOrCachedLocalNumber:(YapDatabaseReadTransaction *)transaction
{
    @synchronized(self) {
        if (self.cachedLocalNumber) {
            return self.cachedLocalNumber;
        }
    }

    return [transaction stringForKey:TSAccountManager_RegisteredNumberKey
                        inCollection:TSAccountManager_UserAccountCollection];
}

- (void)storeLocalNumber:(NSString *)localNumber
{
    @synchronized (self) {
        [self.dbConnection setObject:localNumber
                              forKey:TSAccountManager_RegisteredNumberKey
                        inCollection:TSAccountManager_UserAccountCollection];

        [self.dbConnection removeObjectForKey:TSAccountManager_ReregisteringPhoneNumberKey
                                 inCollection:TSAccountManager_UserAccountCollection];

        self.phoneNumberAwaitingVerification = nil;

        self.cachedLocalNumber = localNumber;
    }
}

+ (uint32_t)getOrGenerateRegistrationId:(YapDatabaseReadWriteTransaction *)transaction
{
    return [[self sharedInstance] getOrGenerateRegistrationId:transaction];
}

- (uint32_t)getOrGenerateRegistrationId
{
    __block uint32_t result;
    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        result = [self getOrGenerateRegistrationId:transaction];
    }];
    return result;
}

- (uint32_t)getOrGenerateRegistrationId:(YapDatabaseReadWriteTransaction *)transaction
{
    // Unlike other methods in this class, there's no need for a `@synchronized` block
    // here, since we're already in a write transaction, and all writes occur on a serial queue.
    //
    // Since other code in this class which uses @synchronized(self) also needs to open write
    // transaction, using @synchronized(self) here, inside of a WriteTransaction risks deadlock.
    uint32_t registrationID = [[transaction objectForKey:TSAccountManager_LocalRegistrationIdKey
                                            inCollection:TSAccountManager_UserAccountCollection] unsignedIntValue];

    if (registrationID == 0) {
        registrationID = (uint32_t)arc4random_uniform(16380) + 1;

        [transaction setObject:[NSNumber numberWithUnsignedInteger:registrationID]
                        forKey:TSAccountManager_LocalRegistrationIdKey
                  inCollection:TSAccountManager_UserAccountCollection];
    }
    return registrationID;
}

- (void)registerForPushNotificationsWithPushToken:(NSString *)pushToken
                                        voipToken:(NSString *)voipToken
                                   isForcedUpdate:(BOOL)isForcedUpdate
                                          success:(void (^)(void))successHandler
                                          failure:(void (^)(NSError *))failureHandler
{
    [self registerForPushNotificationsWithPushToken:pushToken
                                          voipToken:voipToken
                                     isForcedUpdate:isForcedUpdate
                                            success:successHandler
                                            failure:failureHandler
                                   remainingRetries:3];
}

- (void)registerForPushNotificationsWithPushToken:(NSString *)pushToken
                                        voipToken:(NSString *)voipToken
                                   isForcedUpdate:(BOOL)isForcedUpdate
                                          success:(void (^)(void))successHandler
                                          failure:(void (^)(NSError *))failureHandler
                                 remainingRetries:(int)remainingRetries
{
    BOOL isUsingFullAPNs = [NSUserDefaults.standardUserDefaults boolForKey:@"isUsingFullAPNs"];
    NSData *pushTokenAsData = [NSData dataFromHexString:pushToken];
    AnyPromise *promise = isUsingFullAPNs ? [LKPushNotificationAPI registerWithToken:pushTokenAsData hexEncodedPublicKey:self.localNumber isForcedUpdate:isForcedUpdate]
        : [LKPushNotificationAPI unregisterToken:pushTokenAsData];
    promise
    .then(^() {
        successHandler();
    })
    .catch(^(NSError *error) {
        if (remainingRetries > 0) {
            [self registerForPushNotificationsWithPushToken:pushToken voipToken:voipToken isForcedUpdate:isForcedUpdate success:successHandler failure:failureHandler
                remainingRetries:remainingRetries - 1];
        } else {
            failureHandler(error);
        }
    });
}

- (void)rerequestSMSWithCaptchaToken:(nullable NSString *)captchaToken
                             success:(void (^)(void))successBlock
                             failure:(void (^)(NSError *error))failureBlock
{
    // TODO: Can we remove phoneNumberAwaitingVerification?
    NSString *number          = self.phoneNumberAwaitingVerification;

    [self registerWithPhoneNumber:number
                     captchaToken:captchaToken
                          success:successBlock
                          failure:failureBlock
                  smsVerification:YES];
}

- (void)rerequestVoiceWithCaptchaToken:(nullable NSString *)captchaToken
                               success:(void (^)(void))successBlock
                               failure:(void (^)(NSError *error))failureBlock
{
    NSString *number          = self.phoneNumberAwaitingVerification;

    [self registerWithPhoneNumber:number
                     captchaToken:captchaToken
                          success:successBlock
                          failure:failureBlock
                  smsVerification:NO];
}

#pragma mark Server keying material

+ (NSString *)generateNewAccountAuthenticationToken {
    NSData *authToken = [Randomness generateRandomBytes:16];
    NSString *authTokenPrint = [[NSData dataWithData:authToken] hexadecimalString];
    return authTokenPrint;
}

+ (nullable NSString *)signalingKey
{
    return [[self sharedInstance] signalingKey];
}

- (nullable NSString *)signalingKey
{
    return [self.dbConnection stringForKey:TSAccountManager_ServerSignalingKey
                              inCollection:TSAccountManager_UserAccountCollection];
}

+ (nullable NSString *)serverAuthToken
{
    return [[self sharedInstance] serverAuthToken];
}

- (nullable NSString *)serverAuthToken
{
    return [self.dbConnection stringForKey:TSAccountManager_ServerAuthToken
                              inCollection:TSAccountManager_UserAccountCollection];
}

- (void)storeServerAuthToken:(NSString *)authToken
{
    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:authToken
                        forKey:TSAccountManager_ServerAuthToken
                  inCollection:TSAccountManager_UserAccountCollection];
    }];
}

- (void)yapDatabaseModifiedExternally:(NSNotification *)notification
{
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
            self.cachedIsDeregistered = @([self.dbConnection boolForKey:TSAccountManager_IsDeregisteredKey
                                                           inCollection:TSAccountManager_UserAccountCollection
                                                           defaultValue:NO]);
        }

        return self.cachedIsDeregistered.boolValue;
    }
}

- (void)setIsDeregistered:(BOOL)isDeregistered
{
    @synchronized(self) {
        if (self.cachedIsDeregistered && self.cachedIsDeregistered.boolValue == isDeregistered) {
            return;
        }

        self.cachedIsDeregistered = @(isDeregistered);
    }

    [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:@(isDeregistered)
                        forKey:TSAccountManager_IsDeregisteredKey
                  inCollection:TSAccountManager_UserAccountCollection];
    }];

    [self postRegistrationStateDidChangeNotification];
}

- (nullable NSString *)reregisterationPhoneNumber
{
    NSString *_Nullable result = [self.dbConnection stringForKey:TSAccountManager_ReregisteringPhoneNumberKey
                                                    inCollection:TSAccountManager_UserAccountCollection];
    return result;
}

- (BOOL)isReregistering
{
    return nil !=
        [self.dbConnection stringForKey:TSAccountManager_ReregisteringPhoneNumberKey
                           inCollection:TSAccountManager_UserAccountCollection];
}

- (BOOL)hasPendingBackupRestoreDecision
{
    return [self.dbConnection boolForKey:TSAccountManager_HasPendingRestoreDecisionKey
                            inCollection:TSAccountManager_UserAccountCollection
                            defaultValue:NO];
}

- (void)setHasPendingBackupRestoreDecision:(BOOL)value
{
    [self.dbConnection setBool:value
                        forKey:TSAccountManager_HasPendingRestoreDecisionKey
                  inCollection:TSAccountManager_UserAccountCollection];

    [self postRegistrationStateDidChangeNotification];
}

- (BOOL)isManualMessageFetchEnabled
{
    return [self.dbConnection boolForKey:TSAccountManager_ManualMessageFetchKey
                            inCollection:TSAccountManager_UserAccountCollection
                            defaultValue:NO];
}

- (AnyPromise *)setIsManualMessageFetchEnabled:(BOOL)value {
    [self.dbConnection setBool:value
                        forKey:TSAccountManager_ManualMessageFetchKey
                  inCollection:TSAccountManager_UserAccountCollection];

    // Try to update the account attributes to reflect this change.
    return [self updateAccountAttributes];
}

- (void)registerForTestsWithLocalNumber:(NSString *)localNumber
{    
    [self storeLocalNumber:localNumber];
}

#pragma mark - Account Attributes

- (AnyPromise *)updateAccountAttributes {
    // Enqueue a "account attribute update", recording the "request time".
    [self.dbConnection setObject:[NSDate new]
                          forKey:TSAccountManager_NeedsAccountAttributesUpdateKey
                    inCollection:TSAccountManager_UserAccountCollection];

    return [self updateAccountAttributesIfNecessary];
}

- (AnyPromise *)updateAccountAttributesIfNecessary {
    if (!self.isRegistered) {
        return [AnyPromise promiseWithValue:@(1)];
    }

    return [AnyPromise promiseWithValue:@(1)];
    
    NSDate *_Nullable updateRequestDate =
        [self.dbConnection objectForKey:TSAccountManager_NeedsAccountAttributesUpdateKey
                           inCollection:TSAccountManager_UserAccountCollection];
    if (!updateRequestDate) {
        return [AnyPromise promiseWithValue:@(1)];
    }
    AnyPromise *promise = [self performUpdateAccountAttributes];
    promise = promise.then(^(id value) {
        [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            // Clear the update request unless a new update has been requested
            // while this update was in flight.
            NSDate *_Nullable latestUpdateRequestDate =
                [transaction objectForKey:TSAccountManager_NeedsAccountAttributesUpdateKey
                             inCollection:TSAccountManager_UserAccountCollection];
            if (latestUpdateRequestDate && [latestUpdateRequestDate isEqual:updateRequestDate]) {
                [transaction removeObjectForKey:TSAccountManager_NeedsAccountAttributesUpdateKey
                                   inCollection:TSAccountManager_UserAccountCollection];
            }
        }];
    });
    return promise;
}

- (void)reachabilityChanged {
    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [[self updateAccountAttributesIfNecessary] retainUntilComplete];
    }];
}

#pragma mark - Notifications

- (void)postRegistrationStateDidChangeNotification
{
    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:RegistrationStateDidChangeNotification
                                                             object:nil
                                                           userInfo:nil];
}

@end

NS_ASSUME_NONNULL_END
