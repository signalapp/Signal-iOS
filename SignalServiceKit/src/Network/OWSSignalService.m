//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSSignalService.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSCensorshipConfiguration.h"
#import "OWSError.h"
#import "OWSHTTPSecurityPolicy.h"
#import "OWSPrimaryStorage.h"
#import "TSAccountManager.h"
#import "TSConstants.h"
#import <AFNetworking/AFHTTPSessionManager.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kOWSPrimaryStorage_isCensorshipCircumventionManuallyActivated
    = @"kTSStorageManager_isCensorshipCircumventionManuallyActivated";
NSString *const kOWSPrimaryStorage_isCensorshipCircumventionManuallyDisabled
    = @"kTSStorageManager_isCensorshipCircumventionManuallyDisabled";
NSString *const kOWSPrimaryStorage_ManualCensorshipCircumventionDomain
    = @"kTSStorageManager_ManualCensorshipCircumventionDomain";
NSString *const kOWSPrimaryStorage_ManualCensorshipCircumventionCountryCode
    = @"kTSStorageManager_ManualCensorshipCircumventionCountryCode";

NSString *const kNSNotificationName_IsCensorshipCircumventionActiveDidChange =
    @"kNSNotificationName_IsCensorshipCircumventionActiveDidChange";

@interface OWSSignalService ()

@property (atomic) BOOL hasCensoredPhoneNumber;

@property (atomic) BOOL isCensorshipCircumventionActive;

@end

#pragma mark -

@implementation OWSSignalService

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

- (SDSKeyValueStore *)keyValueStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"kTSStorageManager_OWSSignalService"];
}

#pragma mark -


@synthesize isCensorshipCircumventionActive = _isCensorshipCircumventionActive;

+ (instancetype)sharedInstance
{
    static OWSSignalService *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initDefault];
    });
    return sharedInstance;
}

- (instancetype)initDefault
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self observeNotifications];

    [self updateHasCensoredPhoneNumber];
    [self updateIsCensorshipCircumventionActive];

    OWSSingletonAssert();

    return self;
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStateDidChange:)
                                                 name:RegistrationStateDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localNumberDidChange:)
                                                 name:kNSNotificationName_LocalNumberDidChange
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)updateHasCensoredPhoneNumber
{
    NSString *localNumber = [TSAccountManager localNumber];

    if (localNumber) {
        self.hasCensoredPhoneNumber = [OWSCensorshipConfiguration isCensoredPhoneNumber:localNumber];
    } else {
        OWSLogError(@"no known phone number to check for censorship.");
        self.hasCensoredPhoneNumber = NO;
    }

    [self updateIsCensorshipCircumventionActive];
}

- (BOOL)isCensorshipCircumventionManuallyActivated
{
    __block BOOL result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyValueStore getBool:kOWSPrimaryStorage_isCensorshipCircumventionManuallyActivated
                                defaultValue:NO
                                 transaction:transaction];
    }];
    return result;
}

- (void)setIsCensorshipCircumventionManuallyActivated:(BOOL)value
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setBool:value
                                key:kOWSPrimaryStorage_isCensorshipCircumventionManuallyActivated
                        transaction:transaction];
    }];

    [self updateIsCensorshipCircumventionActive];
}

- (BOOL)isCensorshipCircumventionManuallyDisabled
{
    __block BOOL result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyValueStore getBool:kOWSPrimaryStorage_isCensorshipCircumventionManuallyDisabled
                                defaultValue:NO
                                 transaction:transaction];
    }];
    return result;
}

- (void)setIsCensorshipCircumventionManuallyDisabled:(BOOL)value
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setBool:value
                                key:kOWSPrimaryStorage_isCensorshipCircumventionManuallyDisabled
                        transaction:transaction];
    }];

    [self updateIsCensorshipCircumventionActive];
}


- (void)updateIsCensorshipCircumventionActive
{
    if (self.isCensorshipCircumventionManuallyDisabled) {
        self.isCensorshipCircumventionActive = NO;
    } else if (self.isCensorshipCircumventionManuallyActivated) {
        self.isCensorshipCircumventionActive = YES;
    } else if (self.hasCensoredPhoneNumber) {
        self.isCensorshipCircumventionActive = YES;
    } else {
        self.isCensorshipCircumventionActive = NO;
    }
}

- (void)setIsCensorshipCircumventionActive:(BOOL)isCensorshipCircumventionActive
{
    @synchronized(self)
    {
        if (_isCensorshipCircumventionActive == isCensorshipCircumventionActive) {
            return;
        }

        _isCensorshipCircumventionActive = isCensorshipCircumventionActive;
    }

    [[NSNotificationCenter defaultCenter]
        postNotificationNameAsync:kNSNotificationName_IsCensorshipCircumventionActiveDidChange
                           object:nil
                         userInfo:nil];
}

- (BOOL)isCensorshipCircumventionActive
{
    @synchronized(self)
    {
        return _isCensorshipCircumventionActive;
    }
}

- (NSURL *)domainFrontBaseURL
{
    OWSAssertDebug(self.isCensorshipCircumventionActive);
    OWSCensorshipConfiguration *censorshipConfiguration = [self buildCensorshipConfiguration];
    return censorshipConfiguration.domainFrontBaseURL;
}

- (AFHTTPSessionManager *)buildSignalServiceSessionManager
{
    if (self.isCensorshipCircumventionActive) {
        OWSCensorshipConfiguration *censorshipConfiguration = [self buildCensorshipConfiguration];
        OWSLogInfo(@"using reflector HTTPSessionManager via: %@", censorshipConfiguration.domainFrontBaseURL);
        return [self reflectorSignalServiceSessionManagerWithCensorshipConfiguration:censorshipConfiguration];
    } else {
        return self.defaultSignalServiceSessionManager;
    }
}

- (AFHTTPSessionManager *)defaultSignalServiceSessionManager
{
    NSURL *baseURL = [[NSURL alloc] initWithString:textSecureServerURL];
    OWSAssertDebug(baseURL);
    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    AFHTTPSessionManager *sessionManager =
        [[AFHTTPSessionManager alloc] initWithBaseURL:baseURL sessionConfiguration:sessionConf];

    sessionManager.securityPolicy = [OWSHTTPSecurityPolicy sharedPolicy];
    sessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
    sessionManager.responseSerializer = [AFJSONResponseSerializer serializer];
    // Disable default cookie handling for all requests.
    sessionManager.requestSerializer.HTTPShouldHandleCookies = NO;

    return sessionManager;
}

- (AFHTTPSessionManager *)reflectorSignalServiceSessionManagerWithCensorshipConfiguration:
    (OWSCensorshipConfiguration *)censorshipConfiguration
{
    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;

    NSURL *frontingURL = censorshipConfiguration.domainFrontBaseURL;
    NSURL *baseURL = [frontingURL URLByAppendingPathComponent:serviceCensorshipPrefix];
    AFHTTPSessionManager *sessionManager =
        [[AFHTTPSessionManager alloc] initWithBaseURL:baseURL sessionConfiguration:sessionConf];

    sessionManager.securityPolicy = censorshipConfiguration.domainFrontSecurityPolicy;

    sessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
    [sessionManager.requestSerializer setValue:censorshipConfiguration.signalServiceReflectorHost
                            forHTTPHeaderField:@"Host"];
    sessionManager.responseSerializer = [AFJSONResponseSerializer serializer];
    // Disable default cookie handling for all requests.
    sessionManager.requestSerializer.HTTPShouldHandleCookies = NO;

    return sessionManager;
}

#pragma mark - Profile Uploading

- (AFHTTPSessionManager *)CDNSessionManager
{
    AFHTTPSessionManager *result;
    if (self.isCensorshipCircumventionActive) {
        OWSCensorshipConfiguration *censorshipConfiguration = [self buildCensorshipConfiguration];
        OWSLogInfo(@"using reflector CDNSessionManager via: %@", censorshipConfiguration.domainFrontBaseURL);
        result = [self reflectorCDNSessionManagerWithCensorshipConfiguration:censorshipConfiguration];
    } else {
        result = self.defaultCDNSessionManager;
    }
    // By default, CDN content should be binary.
    result.responseSerializer = [AFHTTPResponseSerializer serializer];
    return result;
}

- (AFHTTPSessionManager *)defaultCDNSessionManager
{
    NSURL *baseURL = [[NSURL alloc] initWithString:textSecureCDNServerURL];
    OWSAssertDebug(baseURL);
    
    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    AFHTTPSessionManager *sessionManager =
        [[AFHTTPSessionManager alloc] initWithBaseURL:baseURL sessionConfiguration:sessionConf];

    sessionManager.securityPolicy = [OWSHTTPSecurityPolicy sharedPolicy];
    
    // Default acceptable content headers are rejected by AWS
    sessionManager.responseSerializer.acceptableContentTypes = nil;

    return sessionManager;
}

- (AFHTTPSessionManager *)reflectorCDNSessionManagerWithCensorshipConfiguration:
    (OWSCensorshipConfiguration *)censorshipConfiguration
{
    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;

    NSURL *frontingURL = censorshipConfiguration.domainFrontBaseURL;
    NSURL *baseURL = [frontingURL URLByAppendingPathComponent:cdnCensorshipPrefix];
    AFHTTPSessionManager *sessionManager =
        [[AFHTTPSessionManager alloc] initWithBaseURL:baseURL sessionConfiguration:sessionConf];

    sessionManager.securityPolicy = censorshipConfiguration.domainFrontSecurityPolicy;

    sessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
    [sessionManager.requestSerializer setValue:censorshipConfiguration.CDNReflectorHost forHTTPHeaderField:@"Host"];

    sessionManager.responseSerializer = [AFJSONResponseSerializer serializer];

    return sessionManager;
}

#pragma mark - Storage Service

- (AFHTTPSessionManager *)storageServiceSessionManager
{
    NSURL *baseURL = [[NSURL alloc] initWithString:storageServiceURL];
    OWSAssertDebug(baseURL);

    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    AFHTTPSessionManager *sessionManager = [[AFHTTPSessionManager alloc] initWithBaseURL:baseURL
                                                                    sessionConfiguration:sessionConf];

    sessionManager.securityPolicy = [OWSHTTPSecurityPolicy sharedPolicy];
    sessionManager.requestSerializer = [AFHTTPRequestSerializer serializer];
    sessionManager.responseSerializer = [AFHTTPResponseSerializer serializer];

    // Disable default cookie handling for all requests.
    sessionManager.requestSerializer.HTTPShouldHandleCookies = NO;

    return sessionManager;
}

#pragma mark - Events

- (void)registrationStateDidChange:(NSNotification *)notification
{
    [self updateHasCensoredPhoneNumber];
}

- (void)localNumberDidChange:(NSNotification *)notification
{
    [self updateHasCensoredPhoneNumber];
}

#pragma mark - Manual Censorship Circumvention

- (OWSCensorshipConfiguration *)buildCensorshipConfiguration
{
    OWSAssertDebug(self.isCensorshipCircumventionActive);

    if (self.isCensorshipCircumventionManuallyActivated) {
        NSString *countryCode = self.manualCensorshipCircumventionCountryCode;
        if (countryCode.length == 0) {
            OWSFailDebug(@"manualCensorshipCircumventionCountryCode was unexpectedly 0");
        }

        OWSCensorshipConfiguration *configuration =
            [OWSCensorshipConfiguration censorshipConfigurationWithCountryCode:countryCode];
        OWSAssertDebug(configuration);

        return configuration;
    }

    OWSCensorshipConfiguration *_Nullable configuration =
        [OWSCensorshipConfiguration censorshipConfigurationWithPhoneNumber:TSAccountManager.localNumber];
    if (configuration != nil) {
        return configuration;
    }

    return OWSCensorshipConfiguration.defaultConfiguration;
}

- (nullable NSString *)manualCensorshipCircumventionCountryCode
{
    __block NSString *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyValueStore getString:kOWSPrimaryStorage_ManualCensorshipCircumventionCountryCode
                                   transaction:transaction];
    }];
    return result;
}

- (void)setManualCensorshipCircumventionCountryCode:(nullable NSString *)value
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.keyValueStore setString:value
                                  key:kOWSPrimaryStorage_ManualCensorshipCircumventionCountryCode
                          transaction:transaction];
    }];
}

@end

NS_ASSUME_NONNULL_END
