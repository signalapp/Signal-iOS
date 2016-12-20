// Created by Michael Kirk on 12/20/16.
// Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSSignalService.h"
#import "OWSCensorshipConfiguration.h"
#import "OWSHTTPSecurityPolicy.h"
#import "TSConstants.h"
#import "TSAccountManager.h"
#import "TSStorageManager+keyingMaterial.h"
#import <AFNetworking/AFHTTPSessionManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSAccountManager (OWSSignalService)

@property (nullable, nonatomic, readonly) NSString *phoneNumberAwaitingVerification;

@end

@interface OWSSignalService ()

@property (nonatomic, readonly, strong) TSStorageManager *storageManager;
@property (nonatomic, readonly, strong) TSAccountManager *tsAccountManager;
@property (nonatomic, readonly, strong) OWSCensorshipConfiguration *censorshipConfiguration;

@end

@implementation OWSSignalService

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
                      tsAccountManager:(TSAccountManager *)tsAccountManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _storageManager = storageManager;
    _tsAccountManager = tsAccountManager;
    _censorshipConfiguration = [OWSCensorshipConfiguration new];

    return self;
}

- (BOOL)isCensored
{

    NSString *localNumber = self.storageManager.localNumber;
    NSString *pendingNumber = self.tsAccountManager.phoneNumberAwaitingVerification;

    if (localNumber) {
        if ([self.censorshipConfiguration isCensoredPhoneNumber:localNumber]) {
            DDLogInfo(@"%@ assumed censorship for localNumber: %@", self.tag, localNumber);
            return YES;
        } else {
            DDLogInfo(@"%@ assumed no censorship for localNumber: %@", self.tag, localNumber);
            return NO;
        }
    } else if (pendingNumber) {
        if ([self.censorshipConfiguration isCensoredPhoneNumber:pendingNumber]) {
            DDLogInfo(@"%@ assumed censorship for pending Number: %@", self.tag, pendingNumber);
            return YES;
        } else {
            DDLogInfo(@"%@ assumed no censorship for pending Number: %@", self.tag, pendingNumber);
            return NO;
        }
    } else {
        DDLogError(@"no known phone number to check for censorship.");
        return NO;
    }
}

- (AFHTTPSessionManager *)HTTPSessionManager
{
    if (self.isCensored) {
        return self.reflectorHTTPSessionManager;
    } else {
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
    // Target fronting domain
    NSURL *baseURL = [[NSURL alloc] initWithString:self.censorshipConfiguration.frontingHost];
    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    AFHTTPSessionManager *sessionManager =
        [[AFHTTPSessionManager alloc] initWithBaseURL:baseURL sessionConfiguration:sessionConf];

    // FIXME TODO can we still pin SSL while fronting?
    //    sessionManager.securityPolicy = [OWSHTTPSecurityPolicy sharedPolicy];

    sessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
    [sessionManager.requestSerializer setValue:self.censorshipConfiguration.reflectorHost forHTTPHeaderField:@"Host"];

    sessionManager.responseSerializer = [AFJSONResponseSerializer serializer];

    return sessionManager;
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
