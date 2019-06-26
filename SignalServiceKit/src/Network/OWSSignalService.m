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
#import "YapDatabaseConnection+OWS.h"
#import <AFNetworking/AFHTTPSessionManager.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kOWSPrimaryStorage_OWSSignalService = @"kTSStorageManager_OWSSignalService";
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
    return
        [[OWSPrimaryStorage dbReadConnection] boolForKey:kOWSPrimaryStorage_isCensorshipCircumventionManuallyActivated
                                            inCollection:kOWSPrimaryStorage_OWSSignalService
                                            defaultValue:NO];
}

- (void)setIsCensorshipCircumventionManuallyActivated:(BOOL)value
{
    [[OWSPrimaryStorage dbReadWriteConnection] setObject:@(value)
                                                  forKey:kOWSPrimaryStorage_isCensorshipCircumventionManuallyActivated
                                            inCollection:kOWSPrimaryStorage_OWSSignalService];

    [self updateIsCensorshipCircumventionActive];
}

- (BOOL)isCensorshipCircumventionManuallyDisabled
{
    return [[OWSPrimaryStorage dbReadConnection] boolForKey:kOWSPrimaryStorage_isCensorshipCircumventionManuallyDisabled
                                               inCollection:kOWSPrimaryStorage_OWSSignalService
                                               defaultValue:NO];
}

- (void)setIsCensorshipCircumventionManuallyDisabled:(BOOL)value
{
    [[OWSPrimaryStorage dbReadWriteConnection] setObject:@(value)
                                                  forKey:kOWSPrimaryStorage_isCensorshipCircumventionManuallyDisabled
                                            inCollection:kOWSPrimaryStorage_OWSSignalService];

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
        // On iOS 13 there is a bug that currently prevents us from telling iOS our CDN is trusted.
        // As a workaround, connect to cloudfront directly for now.
        if (@available(iOS 13, *)) {
            result = self.iOS13CDNSessionManager;
        } else {
            result = self.defaultCDNSessionManager;
        }
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

- (AFHTTPSessionManager *)iOS13CDNSessionManager
{
    NSURL *baseURL = [[NSURL alloc] initWithString:textSecureDirectCDNServerURL];
    OWSAssertDebug(baseURL);

    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    AFHTTPSessionManager *sessionManager = [[AFHTTPSessionManager alloc] initWithBaseURL:baseURL
                                                                    sessionConfiguration:sessionConf];

    sessionManager.securityPolicy =
        [OWSCensorshipConfiguration pinningPolicyWithCertNames:@[ @"DigiCertGlobalRootG2" ]];

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
    return
        [[OWSPrimaryStorage dbReadConnection] objectForKey:kOWSPrimaryStorage_ManualCensorshipCircumventionCountryCode
                                              inCollection:kOWSPrimaryStorage_OWSSignalService];
}

- (void)setManualCensorshipCircumventionCountryCode:(nullable NSString *)value
{
    [[OWSPrimaryStorage dbReadWriteConnection] setObject:value
                                                  forKey:kOWSPrimaryStorage_ManualCensorshipCircumventionCountryCode
                                            inCollection:kOWSPrimaryStorage_OWSSignalService];
}

@end

NS_ASSUME_NONNULL_END
