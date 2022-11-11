//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSDeviceProvisioningURLParser.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalServiceKit/NSData+keyVersionByte.h>

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
            NSData *annotatedKey = [NSData dataFromBase64String:encodedPublicKey];

            NSError *_Nullable error = nil;
            _publicKey = [annotatedKey removeKeyTypeAndReturnError:&error];
            if (error) {
                OWSFailDebug(@"failed to strip key type: %@", error);
            }
        } else {
            OWSLogWarn(@"Unknown query item in provisioning string: %@", queryItem.name);
        }
    }

    _valid = _ephemeralDeviceId && _publicKey;
    return self;
}

@end

NS_ASSUME_NONNULL_END
