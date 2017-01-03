// Created by Michael Kirk on 12/20/16.
// Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSSignalService.h"
#import "OWSCensorshipConfiguration.h"
#import "OWSHTTPSecurityPolicy.h"
#import "TSConstants.h"
#import "TSAccountManager.h"
#import <AFNetworking/AFHTTPSessionManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSignalService ()

@property (nonatomic, readonly, strong) OWSCensorshipConfiguration *censorshipConfiguration;

@end

@implementation OWSSignalService

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _censorshipConfiguration = [OWSCensorshipConfiguration new];

    return self;
}

- (BOOL)isCensored
{
    NSString *localNumber = [TSAccountManager localNumber];

    if (localNumber) {
        return [self.censorshipConfiguration isCensoredPhoneNumber:localNumber];
    } else {
        DDLogError(@"no known phone number to check for censorship.");
        return NO;
    }
}

- (AFHTTPSessionManager *)HTTPSessionManager
{
    if (self.isCensored) {
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
