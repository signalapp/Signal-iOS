//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"
#import "TSAccountManager.h"
#import "TSConstants.h"

@implementation TSRequest

- (id)initWithURL:(NSURL *)URL {
    OWSAssert(URL);
    self = [super initWithURL:URL
                  cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
              timeoutInterval:textSecureHTTPTimeOut];
    if (!self) {
        return nil;
    }

    self.parameters = @{};
    self.shouldHaveAuthorizationHeaders = YES;

    return self;
}

- (id)init {
    OWSRaiseException(NSInternalInconsistencyException, @"You must use the initWithURL: method");
    return nil;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

- (id)initWithURL:(NSURL *)URL
      cachePolicy:(NSURLRequestCachePolicy)cachePolicy
  timeoutInterval:(NSTimeInterval)timeoutInterval {
    OWSRaiseException(NSInternalInconsistencyException, @"You must use the initWithURL method");
    return nil;
}

+ (instancetype)requestWithUrl:(NSURL *)url
                        method:(NSString *)method
                    parameters:(NSDictionary<NSString *, id> *)parameters
{
    TSRequest *request = [[TSRequest alloc] initWithURL:url];
    [request setHTTPMethod:method];
    request.parameters = parameters;
    return request;
}

@end
