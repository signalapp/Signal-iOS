//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSSignalService.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSCensorshipConfiguration.h"
#import "OWSError.h"
#import "OWSHTTPSecurityPolicy.h"
#import "TSAccountManager.h"
#import "TSConstants.h"
#import "TSStorageManager.h"
#import <AFNetworking/AFHTTPSessionManager.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kTSStorageManager_OWSSignalService = @"kTSStorageManager_OWSSignalService";
NSString *const kTSStorageManager_isCensorshipCircumventionManuallyActivated =
    @"kTSStorageManager_isCensorshipCircumventionManuallyActivated";
NSString *const kTSStorageManager_ManualCensorshipCircumventionDomain =
    @"kTSStorageManager_ManualCensorshipCircumventionDomain";
NSString *const kTSStorageManager_ManualCensorshipCircumventionCountryCode =
    @"kTSStorageManager_ManualCensorshipCircumventionCountryCode";

NSString *const kNSNotificationName_IsCensorshipCircumventionActiveDidChange =
    @"kNSNotificationName_IsCensorshipCircumventionActiveDidChange";

@interface OWSSignalService ()

@property (nonatomic, readonly) OWSCensorshipConfiguration *censorshipConfiguration;

@property (nonatomic) BOOL hasCensoredPhoneNumber;

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

    _censorshipConfiguration = [OWSCensorshipConfiguration new];

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
                                                 name:kNSNotificationName_RegistrationStateDidChange
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
    OWSAssert([NSThread isMainThread]);

    NSString *localNumber = [TSAccountManager localNumber];

    if (localNumber) {
        self.hasCensoredPhoneNumber = [self.censorshipConfiguration isCensoredPhoneNumber:localNumber];
    } else {
        DDLogError(@"%@ no known phone number to check for censorship.", self.tag);
        self.hasCensoredPhoneNumber = NO;
    }

    [self updateIsCensorshipCircumventionActive];
}

- (BOOL)isCensorshipCircumventionManuallyActivated
{
    return [[TSStorageManager sharedManager] boolForKey:kTSStorageManager_isCensorshipCircumventionManuallyActivated
                                           inCollection:kTSStorageManager_OWSSignalService];
}

- (void)setIsCensorshipCircumventionManuallyActivated:(BOOL)value
{
    OWSAssert([NSThread isMainThread]);

    [[TSStorageManager sharedManager] setObject:@(value)
                                         forKey:kTSStorageManager_isCensorshipCircumventionManuallyActivated
                                   inCollection:kTSStorageManager_OWSSignalService];

    [self updateIsCensorshipCircumventionActive];
}

- (void)updateIsCensorshipCircumventionActive
{
    OWSAssert([NSThread isMainThread]);

    self.isCensorshipCircumventionActive
        = (self.isCensorshipCircumventionManuallyActivated || self.hasCensoredPhoneNumber);
}

- (void)setIsCensorshipCircumventionActive:(BOOL)isCensorshipCircumventionActive
{
    OWSAssert([NSThread isMainThread]);

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

- (AFHTTPSessionManager *)signalServiceSessionManager
{
    if (self.isCensorshipCircumventionActive) {
        DDLogInfo(@"%@ using reflector HTTPSessionManager", self.tag);
        return self.reflectorSignalServiceSessionManager;
    } else {
        return self.defaultSignalServiceSessionManager;
    }
}

- (AFHTTPSessionManager *)defaultSignalServiceSessionManager
{
    NSURL *baseURL = [[NSURL alloc] initWithString:textSecureServerURL];
    OWSAssert(baseURL);
    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    AFHTTPSessionManager *sessionManager =
        [[AFHTTPSessionManager alloc] initWithBaseURL:baseURL sessionConfiguration:sessionConf];

    sessionManager.securityPolicy = [OWSHTTPSecurityPolicy sharedPolicy];
    sessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
    sessionManager.responseSerializer = [AFJSONResponseSerializer serializer];

    return sessionManager;
}

- (NSURL *)domainFrontingBaseURL
{
    NSString *localNumber = [TSAccountManager localNumber];
    OWSAssert(localNumber.length > 0);

    // Target fronting domain
    OWSAssert(self.isCensorshipCircumventionActive);
    NSString *frontingHost = [self.censorshipConfiguration frontingHost:localNumber];
    if (self.isCensorshipCircumventionManuallyActivated && self.manualCensorshipCircumventionDomain.length > 0) {
        frontingHost = self.manualCensorshipCircumventionDomain;
    };
    NSURL *baseURL = [[NSURL alloc] initWithString:[self.censorshipConfiguration frontingHost:localNumber]];
    OWSAssert(baseURL);
    
    return baseURL;
}

- (AFHTTPSessionManager *)reflectorSignalServiceSessionManager
{
    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    AFHTTPSessionManager *sessionManager =
        [[AFHTTPSessionManager alloc] initWithBaseURL:self.domainFrontingBaseURL sessionConfiguration:sessionConf];
    
    sessionManager.securityPolicy = [[self class] googlePinningPolicy];

    sessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
    [sessionManager.requestSerializer setValue:self.censorshipConfiguration.signalServiceReflectorHost forHTTPHeaderField:@"Host"];

    sessionManager.responseSerializer = [AFJSONResponseSerializer serializer];

    return sessionManager;
}

#pragma mark - Profile Uploading

- (AFHTTPSessionManager *)CDNSessionManager
{
    if (self.isCensorshipCircumventionActive) {
        DDLogInfo(@"%@ using reflector CDNSessionManager", self.tag);
        return self.reflectorCDNSessionManager;
    } else {
        return self.defaultCDNSessionManager;
    }
}

- (AFHTTPSessionManager *)defaultCDNSessionManager
{
    NSURL *baseURL = [[NSURL alloc] initWithString:textSecureCDNServerURL];
    OWSAssert(baseURL);
    
    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    AFHTTPSessionManager *sessionManager =
        [[AFHTTPSessionManager alloc] initWithBaseURL:baseURL sessionConfiguration:sessionConf];

    sessionManager.securityPolicy = [OWSHTTPSecurityPolicy sharedPolicy];
    
    // Default acceptable content headers are rejected by AWS
    sessionManager.responseSerializer.acceptableContentTypes = nil;

    return sessionManager;
}

- (AFHTTPSessionManager *)reflectorCDNSessionManager
{
    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    AFHTTPSessionManager *sessionManager =
    [[AFHTTPSessionManager alloc] initWithBaseURL:self.domainFrontingBaseURL sessionConfiguration:sessionConf];
    
    sessionManager.securityPolicy = [[self class] googlePinningPolicy];
    
    sessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
    [sessionManager.requestSerializer setValue:self.censorshipConfiguration.CDNReflectorHost forHTTPHeaderField:@"Host"];
    
    sessionManager.responseSerializer = [AFJSONResponseSerializer serializer];
    
    return sessionManager;
}

#pragma mark - Google Pinning Policy

+ (nullable NSData *)certificateDataWithName:(NSString *)name error:(NSError **)error
{
    if (!name.length) {
        OWSFail(@"%@ expected name with length > 0", self.tag);
        *error = OWSErrorMakeAssertionError();
        return nil;
    }

    NSString *path = [NSBundle.mainBundle pathForResource:name ofType:@"crt"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        OWSFail(@"%@ Missing certificate for name: %@", self.tag, name);
        *error = OWSErrorMakeAssertionError();
        return nil;
    }

    NSData *_Nullable certData = [NSData dataWithContentsOfFile:path options:0 error:error];

    if (*error != nil) {
        OWSFail(@"%@ Failed to read cert file with path: %@", self.tag, path);
        return nil;
    }

    if (certData.length == 0) {
        OWSFail(@"%@ empty certData for name: %@", self.tag, name);
        return nil;
    }

    DDLogVerbose(@"%@ read cert data with name: %@ length: %lu", self.tag, name, certData.length);
    return certData;
}

/**
 * We use the Google Pinning Policy when connecting to our censorship circumventing reflector,
 * which is hosted on Google.
 */
+ (AFSecurityPolicy *)googlePinningPolicy
{
    static AFSecurityPolicy *securityPolicy = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *error;
        NSData *giag2CertData = [self certificateDataWithName:@"GIAG2" error:&error];
        if (error) {
            DDLogError(@"%@ Failed to get GIAG2 certificate data with error: %@", self.tag, error);
            @throw [NSException exceptionWithName:@"OWSSignalService_UnableToReadCertificate"
                                           reason:error.description
                                         userInfo:nil];
        }
        NSData *giag3CertData = [self certificateDataWithName:@"GIAG3" error:&error];
        if (error) {
            DDLogError(@"%@ Failed to get GIAG3 certificate data with error: %@", self.tag, error);
            @throw [NSException exceptionWithName:@"OWSSignalService_UnableToReadCertificate"
                                           reason:error.description
                                         userInfo:nil];
        }

        NSSet<NSData *> *certificates = [NSSet setWithArray:@[ giag2CertData, giag3CertData ]];
        securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeCertificate withPinnedCertificates:certificates];
    });
    return securityPolicy;
}

#pragma mark - Events

- (void)registrationStateDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateHasCensoredPhoneNumber];
    });
}

- (void)localNumberDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateHasCensoredPhoneNumber];
    });
}

#pragma mark - Manual Censorship Circumvention

- (NSString *)manualCensorshipCircumventionDomain
{
    return [[TSStorageManager sharedManager] objectForKey:kTSStorageManager_ManualCensorshipCircumventionDomain
                                             inCollection:kTSStorageManager_OWSSignalService];
}

- (void)setManualCensorshipCircumventionDomain:(NSString *)value
{
    OWSAssert([NSThread isMainThread]);

    [[TSStorageManager sharedManager] setObject:value
                                         forKey:kTSStorageManager_ManualCensorshipCircumventionDomain
                                   inCollection:kTSStorageManager_OWSSignalService];
}

- (NSString *)manualCensorshipCircumventionCountryCode
{
    OWSAssert([NSThread isMainThread]);

    return [[TSStorageManager sharedManager] objectForKey:kTSStorageManager_ManualCensorshipCircumventionCountryCode
                                             inCollection:kTSStorageManager_OWSSignalService];
}

- (void)setManualCensorshipCircumventionCountryCode:(NSString *)value
{
    OWSAssert([NSThread isMainThread]);

    [[TSStorageManager sharedManager] setObject:value
                                         forKey:kTSStorageManager_ManualCensorshipCircumventionCountryCode
                                   inCollection:kTSStorageManager_OWSSignalService];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
