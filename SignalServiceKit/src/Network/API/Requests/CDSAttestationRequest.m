//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "CDSAttestationRequest.h"

NS_ASSUME_NONNULL_BEGIN

@implementation CDSAttestationRequest

- (TSRequest *)initWithURL:(NSURL *)URL
                    method:(NSString *)method
                parameters:(nullable NSDictionary<NSString *, id> *)parameters
                  username:(NSString *)username
                 authToken:(NSString *)authToken
{
    OWSAssert(authToken.length > 0);

    if (self = [super initWithURL:URL method:method parameters:parameters]) {
        _username = username;
        _authToken = authToken;
    }

    return self;
}

@end

NS_ASSUME_NONNULL_END
