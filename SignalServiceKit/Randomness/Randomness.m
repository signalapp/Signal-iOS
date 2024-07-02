//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "Randomness.h"

NS_ASSUME_NONNULL_BEGIN

@implementation Randomness

+ (NSData *)generateRandomBytes:(NSUInteger)numberBytes
{
    NSMutableData *_Nullable randomBytes = [NSMutableData dataWithLength:numberBytes];
    if (!randomBytes) {
        OWSFail(@"Could not allocate buffer for random bytes.");
    }
    int err = 0;
    err = SecRandomCopyBytes(kSecRandomDefault, numberBytes, [randomBytes mutableBytes]);
    if (err != noErr || randomBytes.length != numberBytes) {
        OWSFail(@"Could not generate random bytes.");
    }
    NSData *copy = [randomBytes copy];

    OWSPrecondition(copy != nil);
    OWSPrecondition(copy.length == numberBytes);
    return copy;
}

@end

NS_ASSUME_NONNULL_END
