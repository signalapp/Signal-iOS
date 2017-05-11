//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <AFNetworking/AFHTTPSessionManager.h>

#import "OWSSignalService.h"
#import "OWSCensorshipConfiguration.h"
#import "OWSHTTPSecurityPolicy.h"
#import "TSConstants.h"
#import "TSAccountManager.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const kNSUserDefaults_isCensorshipCircumventionManuallyActivated =
    @"kNSUserDefaults_isCensorshipCircumventionManuallyActivated";
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
    OWSAssert([NSThread isMainThread]);

    return [[NSUserDefaults.standardUserDefaults
        objectForKey:kNSUserDefaults_isCensorshipCircumventionManuallyActivated] boolValue];
}

- (void)setIsCensorshipCircumventionManuallyActivated:(BOOL)value
{
    OWSAssert([NSThread isMainThread]);

    [NSUserDefaults.standardUserDefaults setObject:@(value)
                                            forKey:kNSUserDefaults_isCensorshipCircumventionManuallyActivated];
    [NSUserDefaults.standardUserDefaults synchronize];

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
        postNotificationName:kNSNotificationName_IsCensorshipCircumventionActiveDidChange
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

- (AFHTTPSessionManager *)HTTPSessionManager
{
    if (self.isCensorshipCircumventionActive) {
        DDLogInfo(@"%@ using reflector HTTPSessionManager", self.tag);
        return self.reflectorHTTPSessionManager;
    } else {
        DDLogDebug(@"%@ using default HTTPSessionManager", self.tag);
        return self.defaultHTTPSessionManager;
    }
}

- (AFHTTPSessionManager *)defaultHTTPSessionManager
{
    NSURL *baseURL = [[NSURL alloc] initWithString:textSecureServerURL];
    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    AFHTTPSessionManager *sessionManager =
        [[AFHTTPSessionManager alloc] initWithBaseURL:baseURL sessionConfiguration:sessionConf];

    sessionManager.securityPolicy = [OWSHTTPSecurityPolicy sharedPolicy];
    sessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
    sessionManager.responseSerializer = [AFJSONResponseSerializer serializer];

    return sessionManager;
}

- (AFHTTPSessionManager *)reflectorHTTPSessionManager
{
    NSString *localNumber = [TSAccountManager localNumber];
    OWSAssert(localNumber.length > 0);

    // Target fronting domain
    NSURL *baseURL = [[NSURL alloc] initWithString:[self.censorshipConfiguration frontingHost:localNumber]];
    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    AFHTTPSessionManager *sessionManager =
        [[AFHTTPSessionManager alloc] initWithBaseURL:baseURL sessionConfiguration:sessionConf];
    
    sessionManager.securityPolicy = [[self class] googlePinningPolicy];

    sessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
    [sessionManager.requestSerializer setValue:self.censorshipConfiguration.reflectorHost forHTTPHeaderField:@"Host"];

    sessionManager.responseSerializer = [AFJSONResponseSerializer serializer];

    return sessionManager;
}

#pragma mark - Google Pinning Policy

/**
 * We use the Google Pinning Policy when connecting to our censorship circumventing reflector,
 * which is hosted on Google.
 */
+ (AFSecurityPolicy *)googlePinningPolicy {
    static AFSecurityPolicy *securityPolicy = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *error;
        NSString *path = [NSBundle.mainBundle pathForResource:@"GIAG2" ofType:@"crt"];

        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            @throw [NSException
                    exceptionWithName:@"Missing server certificate"
                    reason:[NSString stringWithFormat:@"Missing signing certificate for service googlePinningPolicy"]
                    userInfo:nil];
        }
        
        NSData *googleCertData = [NSData dataWithContentsOfFile:path options:0 error:&error];
        if (!googleCertData) {
            if (error) {
                @throw [NSException exceptionWithName:@"OWSSignalServiceHTTPSecurityPolicy" reason:@"Couln't read google pinning cert" userInfo:nil];
            } else {
                NSString *reason = [NSString stringWithFormat:@"Reading google pinning cert faile with error: %@", error];
                @throw [NSException exceptionWithName:@"OWSSignalServiceHTTPSecurityPolicy" reason:reason userInfo:nil];
            }
        }
        
        NSSet<NSData *> *certificates = [NSSet setWithObject:googleCertData];
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
