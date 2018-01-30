//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSAccountManager.h"
#import "AppContext.h"
#import "NSData+Base64.h"
#import "NSData+hexString.h"
#import "NSNotificationCenter+OWS.h"
#import "NSURLSessionDataTask+StatusCode.h"
#import "OWSError.h"
#import "SecurityUtils.h"
#import "TSNetworkManager.h"
#import "TSPreKeyManager.h"
#import "TSSocketManager.h"
#import "TSStorageManager+SessionStore.h"
#import "YapDatabaseConnection+OWS.h"
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSRegistrationErrorDomain = @"TSRegistrationErrorDomain";
NSString *const TSRegistrationErrorUserInfoHTTPStatus = @"TSHTTPStatus";
NSString *const RegistrationStateDidChangeNotification = @"RegistrationStateDidChangeNotification";
NSString *const kNSNotificationName_LocalNumberDidChange = @"kNSNotificationName_LocalNumberDidChange";

NSString *const TSAccountManager_RegisteredNumberKey = @"TSStorageRegisteredNumberKey";
NSString *const TSAccountManager_LocalRegistrationIdKey = @"TSStorageLocalRegistrationId";

NSString *const TSAccountManager_UserAccountCollection = @"TSStorageUserAccountCollection";
NSString *const TSAccountManager_ServerAuthToken = @"TSStorageServerAuthToken";
NSString *const TSAccountManager_ServerSignalingKey = @"TSStorageServerSignalingKey";

@interface TSAccountManager ()

@property (nonatomic, readonly) BOOL isRegistered;
@property (nonatomic, nullable) NSString *phoneNumberAwaitingVerification;
@property (nonatomic, nullable) NSString *cachedLocalNumber;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

#pragma mark -

@implementation TSAccountManager

@synthesize isRegistered = _isRegistered;

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
                        storageManager:(TSStorageManager *)storageManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _networkManager = networkManager;
    _dbConnection = [storageManager newDatabaseConnection];

    OWSSingletonAssert();

    if (!CurrentAppContext().isMainApp) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(yapDatabaseModifiedExternally:)
                                                     name:YapDatabaseModifiedExternallyNotification
                                                   object:nil];
    }

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    static id sharedInstance = nil;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initWithNetworkManager:[TSNetworkManager sharedManager]
                                               storageManager:[TSStorageManager sharedManager]];
    });

    return sharedInstance;
}

- (void)setPhoneNumberAwaitingVerification:(NSString *_Nullable)phoneNumberAwaitingVerification
{
    _phoneNumberAwaitingVerification = phoneNumberAwaitingVerification;

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:kNSNotificationName_LocalNumberDidChange
                                                             object:nil
                                                           userInfo:nil];
}

- (void)resetForRegistration
{
    @synchronized(self)
    {
        _isRegistered = NO;
        _cachedLocalNumber = nil;
        _phoneNumberAwaitingVerification = nil;
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            [transaction removeAllObjectsInCollection:TSAccountManager_UserAccountCollection];
        }];
    }
    [[TSStorageManager sharedManager] resetSessionStore];
}

+ (BOOL)isRegistered
{
    return [[self sharedInstance] isRegistered];
}

- (BOOL)isRegistered
{
    if (_isRegistered) {
        return YES;
    } else {
        @synchronized (self) {
            // Cache this once it's true since it's called alot, involves a dbLookup, and once set - it doesn't change.
            _isRegistered = [self storedLocalNumber] != nil;
        }
    }
    return _isRegistered;
}

- (void)didRegister
{
    DDLogInfo(@"%@ didRegister", self.logTag);
    NSString *phoneNumber = self.phoneNumberAwaitingVerification;

    if (!phoneNumber) {
        OWSRaiseException(@"RegistrationFail", @"Internal Corrupted State");
    }

    [self storeLocalNumber:phoneNumber];

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:RegistrationStateDidChangeNotification
                                                             object:nil
                                                           userInfo:nil];

    // Warm these cached values.
    [self isRegistered];
    [self localNumber];
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

- (void)storeLocalNumber:(NSString *)localNumber
{
    @synchronized (self) {
        [self.dbConnection setObject:localNumber
                              forKey:TSAccountManager_RegisteredNumberKey
                        inCollection:TSAccountManager_UserAccountCollection];
    }
}

+ (uint32_t)getOrGenerateRegistrationId
{
    return [[self sharedInstance] getOrGenerateRegistrationId];
}

+ (uint32_t)getOrGenerateRegistrationId:(YapDatabaseReadWriteTransaction *)transaction
{
    return [[self sharedInstance] getOrGenerateRegistrationId:transaction];
}

- (uint32_t)getOrGenerateRegistrationId
{
    __block uint32_t result;
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        result = [self getOrGenerateRegistrationId:transaction];
    }];
    return result;
}

- (uint32_t)getOrGenerateRegistrationId:(YapDatabaseReadWriteTransaction *)transaction
{
    @synchronized(self)
    {
        uint32_t registrationID = [[transaction objectForKey:TSAccountManager_LocalRegistrationIdKey
                                                inCollection:TSAccountManager_UserAccountCollection] unsignedIntValue];

        if (registrationID == 0) {
            registrationID = (uint32_t)arc4random_uniform(16380) + 1;
            DDLogWarn(@"%@ Generated a new registrationID: %u", self.logTag, registrationID);

            [transaction setObject:[NSNumber numberWithUnsignedInteger:registrationID]
                            forKey:TSAccountManager_LocalRegistrationIdKey
                      inCollection:TSAccountManager_UserAccountCollection];
        }
        return registrationID;
    }
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
    TSRegisterForPushRequest *request =
        [[TSRegisterForPushRequest alloc] initWithPushIdentifier:pushToken voipIdentifier:voipToken];

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

+ (void)registerWithPhoneNumber:(NSString *)phoneNumber
                        success:(void (^)(void))successBlock
                        failure:(void (^)(NSError *error))failureBlock
                smsVerification:(BOOL)isSMS

{
    if ([self isRegistered]) {
        failureBlock([NSError errorWithDomain:@"tsaccountmanager.verify" code:4000 userInfo:nil]);
        return;
    }

    // The country code of TSAccountManager.phoneNumberAwaitingVerification is used to
    // determine whether or not to use domain fronting, so it needs to be set _before_
    // we make our verification code request.
    TSAccountManager *manager = [self sharedInstance];
    manager.phoneNumberAwaitingVerification = phoneNumber;

    [[TSNetworkManager sharedManager]
        makeRequest:[[TSRequestVerificationCodeRequest alloc]
                        initWithPhoneNumber:phoneNumber
                                  transport:isSMS ? TSVerificationTransportSMS : TSVerificationTransportVoice]
        success:^(NSURLSessionDataTask *task, id responseObject) {
            DDLogInfo(@"%@ Successfully requested verification code request for number: %@ method:%@",
                self.logTag,
                phoneNumber,
                isSMS ? @"SMS" : @"Voice");
            successBlock();
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNSErrorNetworkFailure(error)) {
                OWSProdError([OWSAnalyticsEvents accountsErrorVerificationCodeRequestFailed]);
            }
            DDLogError(@"%@ Failed to request verification code request with error:%@", self.logTag, error);
            failureBlock(error);
        }];
}

+ (void)rerequestSMSWithSuccess:(void (^)(void))successBlock failure:(void (^)(NSError *error))failureBlock
{
    TSAccountManager *manager = [self sharedInstance];
    NSString *number          = manager.phoneNumberAwaitingVerification;

    assert(number);

    [self registerWithPhoneNumber:number success:successBlock failure:failureBlock smsVerification:YES];
}

+ (void)rerequestVoiceWithSuccess:(void (^)(void))successBlock failure:(void (^)(NSError *error))failureBlock
{
    TSAccountManager *manager = [self sharedInstance];
    NSString *number          = manager.phoneNumberAwaitingVerification;

    assert(number);

    [self registerWithPhoneNumber:number success:successBlock failure:failureBlock smsVerification:NO];
}

- (void)registerForManualMessageFetchingWithSuccess:(void (^)(void))successBlock
                                            failure:(void (^)(NSError *error))failureBlock
{
    TSUpdateAttributesRequest *request = [[TSUpdateAttributesRequest alloc] initWithManualMessageFetching:YES];
    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *_Nonnull task, id _Nonnull responseObject) {
            DDLogInfo(@"%@ updated server with account attributes to enableManualFetching", self.logTag);
            successBlock();
        }
        failure:^(NSURLSessionDataTask *_Nonnull task, NSError *_Nonnull error) {
            DDLogInfo(@"%@ failed to updat server with account attributes with error: %@", self.logTag, error);
            failureBlock(error);
        }];
}

- (void)verifyAccountWithCode:(NSString *)verificationCode
                      success:(void (^)(void))successBlock
                      failure:(void (^)(NSError *error))failureBlock
{
    NSString *authToken = [[self class] generateNewAccountAuthenticationToken];
    NSString *signalingKey = [[self class] generateNewSignalingKeyToken];
    NSString *phoneNumber = self.phoneNumberAwaitingVerification;

    assert(signalingKey);
    assert(authToken);
    assert(phoneNumber);

    TSVerifyCodeRequest *request = [[TSVerifyCodeRequest alloc] initWithVerificationCode:verificationCode
                                                                               forNumber:phoneNumber
                                                                            signalingKey:signalingKey
                                                                                 authKey:authToken];

    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            long statuscode = response.statusCode;

            switch (statuscode) {
                case 200:
                case 204: {
                    DDLogInfo(@"%@ Verification code accepted.", self.logTag);
                    [self storeServerAuthToken:authToken signalingKey:signalingKey];
                    [TSPreKeyManager registerPreKeysWithMode:RefreshPreKeysMode_SignedAndOneTime
                                                     success:successBlock
                                                     failure:failureBlock];
                    break;
                }
                default: {
                    DDLogError(@"%@ Unexpected status while verifying code: %ld", self.logTag, statuscode);
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
            DDLogWarn(@"%@ Error verifying code: %@", self.logTag, error.debugDescription);
            switch (error.code) {
                case 403: {
                    NSError *userError = OWSErrorWithCodeDescription(OWSErrorCodeUserError,
                        NSLocalizedString(@"REGISTRATION_VERIFICATION_FAILED_WRONG_CODE_DESCRIPTION",
                            "Alert body, during registration"));
                    failureBlock(userError);
                    break;
                }
                default: {
                    DDLogError(@"%@ verifying code failed with unhandled error: %@", self.logTag, error);
                    failureBlock(error);
                    break;
                }
            }
        }];
}

#pragma mark Server keying material

+ (NSString *)generateNewAccountAuthenticationToken {
    NSData *authToken        = [SecurityUtils generateRandomBytes:16];
    NSString *authTokenPrint = [[NSData dataWithData:authToken] hexadecimalString];
    return authTokenPrint;
}

+ (NSString *)generateNewSignalingKeyToken {
    /*The signalingKey is 32 bytes of AES material (256bit AES) and 20 bytes of
     * Hmac key material (HmacSHA1) concatenated into a 52 byte slug that is
     * base64 encoded. */
    NSData *signalingKeyToken        = [SecurityUtils generateRandomBytes:52];
    NSString *signalingKeyTokenPrint = [[NSData dataWithData:signalingKeyToken] base64EncodedString];
    return signalingKeyTokenPrint;
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

- (void)storeServerAuthToken:(NSString *)authToken signalingKey:(NSString *)signalingKey
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:authToken
                        forKey:TSAccountManager_ServerAuthToken
                  inCollection:TSAccountManager_UserAccountCollection];
        [transaction setObject:signalingKey
                        forKey:TSAccountManager_ServerSignalingKey
                  inCollection:TSAccountManager_UserAccountCollection];

    }];
}

+ (void)unregisterTextSecureWithSuccess:(void (^)(void))success failure:(void (^)(NSError *error))failureBlock
{
    [[TSNetworkManager sharedManager] makeRequest:[[TSUnregisterAccountRequest alloc] init]
        success:^(NSURLSessionDataTask *task, id responseObject) {
            DDLogInfo(@"%@ Successfully unregistered", self.logTag);
            success();

            // This is called from `[AppSettingsViewController proceedToUnregistration]` whose
            // success handler calls `[Environment resetAppData]`.
            // This method, after calling that success handler, fires
            // `RegistrationStateDidChangeNotification` which is only safe to fire after
            // the data store is reset.

            [[NSNotificationCenter defaultCenter] postNotificationNameAsync:RegistrationStateDidChangeNotification
                                                                     object:nil
                                                                   userInfo:nil];
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNSErrorNetworkFailure(error)) {
                OWSProdError([OWSAnalyticsEvents accountsErrorUnregisterAccountRequestFailed]);
            }
            DDLogError(@"%@ Failed to unregister with error: %@", self.logTag, error);
            failureBlock(error);
        }];
}

- (void)yapDatabaseModifiedExternally:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    // Any database write by the main app might reflect a deregistration,
    // so clear the cached "is registered" state.  This will significantly
    // erode the value of this cache in the SAE.
    @synchronized(self)
    {
        _isRegistered = NO;
    }
}

@end

NS_ASSUME_NONNULL_END
