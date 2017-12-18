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
        self.hasCensoredPhoneNumber = [self.censorshipConfiguration isCensoredPhoneNumber:localNumber];
    } else {
        DDLogError(@"%@ no known phone number to check for censorship.", self.logTag);
        self.hasCensoredPhoneNumber = NO;
    }

    [self updateIsCensorshipCircumventionActive];
}

- (BOOL)isCensorshipCircumventionManuallyActivated
{
    return [[TSStorageManager dbReadConnection] boolForKey:kTSStorageManager_isCensorshipCircumventionManuallyActivated
                                              inCollection:kTSStorageManager_OWSSignalService];
}

- (void)setIsCensorshipCircumventionManuallyActivated:(BOOL)value
{
    [[TSStorageManager dbReadWriteConnection] setObject:@(value)
                                                 forKey:kTSStorageManager_isCensorshipCircumventionManuallyActivated
                                           inCollection:kTSStorageManager_OWSSignalService];

    [self updateIsCensorshipCircumventionActive];
}

- (void)updateIsCensorshipCircumventionActive
{
    self.isCensorshipCircumventionActive
        = (self.isCensorshipCircumventionManuallyActivated || self.hasCensoredPhoneNumber);
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

- (AFHTTPSessionManager *)signalServiceSessionManager
{
    if (self.isCensorshipCircumventionActive) {
        DDLogInfo(@"%@ using reflector HTTPSessionManager via: %@", self.logTag, self.domainFrontingBaseURL);
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
    
    NSURL *baseURL;

    if (self.isCensorshipCircumventionManuallyActivated && self.manualCensorshipCircumventionDomain.length > 0) {
        baseURL = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"https://%@", self.manualCensorshipCircumventionDomain]];
    }
    
    if (baseURL == nil) {
        baseURL = [[NSURL alloc] initWithString:[self.censorshipConfiguration frontingHost:localNumber]];
    }
    
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
        DDLogInfo(@"%@ using reflector CDNSessionManager via: %@", self.logTag, self.domainFrontingBaseURL);
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
        OWSFail(@"%@ expected name with length > 0", self.logTag);
        *error = OWSErrorMakeAssertionError();
        return nil;
    }

    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *path = [bundle pathForResource:name ofType:@"crt"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        OWSFail(@"%@ Missing certificate for name: %@", self.logTag, name);
        *error = OWSErrorMakeAssertionError();
        return nil;
    }

    NSData *_Nullable certData = [NSData dataWithContentsOfFile:path options:0 error:error];

    if (*error != nil) {
        OWSFail(@"%@ Failed to read cert file with path: %@", self.logTag, path);
        return nil;
    }

    if (certData.length == 0) {
        OWSFail(@"%@ empty certData for name: %@", self.logTag, name);
        return nil;
    }

    DDLogVerbose(@"%@ read cert data with name: %@ length: %lu", self.logTag, name, (unsigned long)certData.length);
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

        NSMutableSet<NSData *> *certificates = [NSMutableSet new];

        // GIAG2 cert plus root certs from pki.goog
        NSArray<NSString *> *certNames = @[ @"GIAG2", @"GSR2", @"GSR4", @"GTSR1", @"GTSR2", @"GTSR3", @"GTSR4" ];

        for (NSString *certName in certNames) {
            NSError *error;
            NSData *certData = [self certificateDataWithName:certName error:&error];
            if (error) {
                DDLogError(@"%@ Failed to get %@ certificate data with error: %@", self.logTag, certName, error);
                @throw [NSException exceptionWithName:@"OWSSignalService_UnableToReadCertificate"
                                               reason:error.description
                                             userInfo:nil];
            }

            if (!certData) {
                DDLogError(@"%@ No data for certificate: %@", self.logTag, certName);
                @throw [NSException exceptionWithName:@"OWSSignalService_UnableToReadCertificate"
                                               reason:error.description
                                             userInfo:nil];
            }
            [certificates addObject:certData];
        }

        securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeCertificate withPinnedCertificates:certificates];
    });
    return securityPolicy;
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

- (NSString *)manualCensorshipCircumventionDomain
{
    return [[TSStorageManager dbReadConnection] objectForKey:kTSStorageManager_ManualCensorshipCircumventionDomain
                                                inCollection:kTSStorageManager_OWSSignalService];
}

- (void)setManualCensorshipCircumventionDomain:(NSString *)value
{
    [[TSStorageManager dbReadWriteConnection] setObject:value
                                                 forKey:kTSStorageManager_ManualCensorshipCircumventionDomain
                                           inCollection:kTSStorageManager_OWSSignalService];
}

- (NSString *)manualCensorshipCircumventionCountryCode
{
    return [[TSStorageManager dbReadConnection] objectForKey:kTSStorageManager_ManualCensorshipCircumventionCountryCode
                                                inCollection:kTSStorageManager_OWSSignalService];
}

- (void)setManualCensorshipCircumventionCountryCode:(NSString *)value
{
    [[TSStorageManager dbReadWriteConnection] setObject:value
                                                 forKey:kTSStorageManager_ManualCensorshipCircumventionCountryCode
                                           inCollection:kTSStorageManager_OWSSignalService];
}

@end

NS_ASSUME_NONNULL_END
