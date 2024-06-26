//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "Cryptography.h"
#import "NSData+OWS.h"
#import "Randomness.h"

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kAES256_KeyByteLength = 32;

@implementation OWSAES256Key

+ (nullable instancetype)keyWithData:(NSData *)data
{
    if (data.length != kAES256_KeyByteLength) {
        OWSLogError(@"Invalid key length: %lu", (unsigned long)data.length);
        return nil;
    }

    return [[self alloc] initWithData:data];
}

+ (instancetype)generateRandomKey
{
    return [self new];
}

- (instancetype)init
{
    return [self initWithData:[Cryptography generateRandomBytes:kAES256_KeyByteLength]];
}

- (instancetype)initWithData:(NSData *)data
{
    self = [super init];
    if (!self) {
        return self;
    }

    _keyData = data;

    return self;
}

#pragma mark - SecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (!self) {
        return self;
    }

    NSData *keyData = [aDecoder decodeObjectOfClass:[NSData class] forKey:@"keyData"];
    if (keyData.length != kAES256_KeyByteLength) {
        OWSFailDebug(@"Invalid key length: %lu", (unsigned long)keyData.length);
        return nil;
    }

    _keyData = keyData;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_keyData forKey:@"keyData"];
}

- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:[OWSAES256Key class]]) {
        OWSAES256Key *otherKey = (OWSAES256Key *)object;
        return [otherKey.keyData ows_constantTimeIsEqualToData:self.keyData];
    }

    return NO;
}

- (NSUInteger)hash
{
    return self.keyData.hash;
}

@end

#pragma mark -

@implementation Cryptography

#pragma mark - random bytes methods

+ (NSData *)generateRandomBytes:(NSUInteger)numberBytes
{
    return [Randomness generateRandomBytes:(int)numberBytes];
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
