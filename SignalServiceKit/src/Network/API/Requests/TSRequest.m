//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"
#import "TSAccountManager.h"
#import "TSConstants.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalMetadataKit/SignalMetadataKit-Swift.h>
#import <SignalServiceKit/SSKEnvironment.h>

NS_ASSUME_NONNULL_BEGIN

@implementation TSRequest

@synthesize authUsername = _authUsername;
@synthesize authPassword = _authPassword;

- (id)initWithURL:(NSURL *)URL {
    OWSAssertDebug(URL);
    self = [super initWithURL:URL
                  cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
              timeoutInterval:textSecureHTTPTimeOut];
    if (!self) {
        return nil;
    }

    _parameters = @{};
    self.shouldHaveAuthorizationHeaders = YES;

    return self;
}

- (instancetype)init
{
    OWSFail(@"You must use the initWithURL: method");
    return nil;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

- (instancetype)initWithURL:(NSURL *)URL
                cachePolicy:(NSURLRequestCachePolicy)cachePolicy
            timeoutInterval:(NSTimeInterval)timeoutInterval
{
    OWSFail(@"You must use the initWithURL: method");
    return nil;
}

- (instancetype)initWithURL:(NSURL *)URL
                     method:(NSString *)method
                 parameters:(nullable NSDictionary<NSString *, id> *)parameters
{
    OWSAssertDebug(URL);
    OWSAssertDebug(method.length > 0);
    OWSAssertDebug(parameters);

    self = [super initWithURL:URL
                  cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
              timeoutInterval:textSecureHTTPTimeOut];
    if (!self) {
        return nil;
    }

    _parameters = parameters ?: @{};
    [self setHTTPMethod:method];
    self.shouldHaveAuthorizationHeaders = YES;

    return self;
}

+ (instancetype)requestWithUrl:(NSURL *)url
                        method:(NSString *)method
                    parameters:(nullable NSDictionary<NSString *, id> *)parameters
{
    return [[TSRequest alloc] initWithURL:url method:method parameters:parameters];
}

#pragma mark - Dependencies

- (TSAccountManager *)tsAccountManager
{
    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark - Authorization

- (void)setAuthUsername:(nullable NSString *)authUsername
{
    OWSAssertDebug(self.shouldHaveAuthorizationHeaders);

    @synchronized(self) {
        _authUsername = authUsername;
    }
}

- (void)setAuthPassword:(nullable NSString *)authPassword
{
    OWSAssertDebug(self.shouldHaveAuthorizationHeaders);

    @synchronized(self) {
        _authPassword = authPassword;
    }
}

- (nullable NSString *)authUsername
{
    OWSAssertDebug(self.shouldHaveAuthorizationHeaders);

    @synchronized(self) {
        return (_authUsername ?: [TSAccountManager localNumber]);
    }
}

- (nullable NSString *)authPassword
{
    OWSAssertDebug(self.shouldHaveAuthorizationHeaders);

    @synchronized(self) {
        return (_authPassword ?: self.tsAccountManager.storedServerAuthToken);
    }
}

@end

NS_ASSUME_NONNULL_END
