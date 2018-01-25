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
    self.parameters = [NSMutableDictionary dictionary];

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

#pragma clang diagnostic pop

- (void)makeAuthenticatedRequest {
    OWSAssert([TSAccountManager serverAuthToken]);
    [self.parameters addEntriesFromDictionary:@{ @"Authorization" : [TSAccountManager serverAuthToken] }];
}

@end
