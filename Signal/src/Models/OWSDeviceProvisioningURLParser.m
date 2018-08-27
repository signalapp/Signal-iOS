//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDeviceProvisioningURLParser.h"
#import "NSData+OWS.h"
#import <AxolotlKit/NSData+keyVersionByte.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSQueryItemNameEphemeralDeviceIdKey = @"uuid";
NSString *const OWSQueryItemNameEncodedPublicKeyKey = @"pub_key";

@implementation OWSDeviceProvisioningURLParser

- (instancetype)initWithProvisioningURL:(NSString *)provisioningURL
{
    self = [super init];
    if (!self) {
        return self;
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:provisioningURL];
    for (NSURLQueryItem *queryItem in [components queryItems]) {
        if ([queryItem.name isEqualToString:OWSQueryItemNameEphemeralDeviceIdKey]) {
            _ephemeralDeviceId = queryItem.value;
        } else if ([queryItem.name isEqualToString:OWSQueryItemNameEncodedPublicKeyKey]) {
            NSString *encodedPublicKey = queryItem.value;
            _publicKey = [[NSData dataFromBase64String:encodedPublicKey] removeKeyType];
        } else {
            OWSLogWarn(@"Unkown query item in provisioning string: %@", queryItem.name);
        }
    }

    _valid = _ephemeralDeviceId && _publicKey;
    return self;
}

@end

NS_ASSUME_NONNULL_END
