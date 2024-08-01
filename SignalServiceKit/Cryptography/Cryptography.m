//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "Cryptography.h"
#import "NSData+OWS.h"
#import "SignalServiceKit/SignalServiceKit-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@implementation Cryptography

#pragma mark - random bytes methods

+ (NSData *)generateRandomBytes:(NSUInteger)numberBytes
{
    return [Randomness generateRandomBytes:numberBytes];
}

+ (uint64_t)randomUInt64
{
    size_t size = sizeof(uint64_t);
    NSData *data = [self generateRandomBytes:size];
    uint64_t result = 0;
    [data getBytes:&result range:NSMakeRange(0, size)];
    return result;
}

+ (unsigned)randomUnsigned
{
    size_t size = sizeof(unsigned);
    NSData *data = [self generateRandomBytes:size];
    unsigned result = 0;
    [data getBytes:&result range:NSMakeRange(0, size)];
    return result;
}

#pragma mark -

+ (void)seedRandom
{
    // We should never use rand(), but seed it just in case it's used by 3rd-party code
    unsigned seed = [Cryptography randomUnsigned];
    srand(seed);
}

@end

NS_ASSUME_NONNULL_END
