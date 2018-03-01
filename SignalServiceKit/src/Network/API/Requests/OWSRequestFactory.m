//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSRequestFactory.h"
#import "TSConstants.h"
#import "TSRequest.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSRequestFactory

+ (TSRequest *)enable2FARequestWithPin:(NSString *)pin;
{
    OWSAssert(pin.length > 0);

    return [TSRequest requestWithUrl:[NSURL URLWithString:textSecure2FAAPI]
                              method:@"PUT"
                          parameters:@{
                              @"pin" : pin,
                          }];
}

+ (TSRequest *)disable2FARequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:textSecure2FAAPI] method:@"DELETE" parameters:@{}];
}

@end

NS_ASSUME_NONNULL_END
