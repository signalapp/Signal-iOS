//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kAES256_KeyByteLength;

/// Key appropriate for use in AES256-GCM
@interface OWSAES256Key : NSObject <NSSecureCoding>

/// Generates new secure random key
- (instancetype)init;
+ (instancetype)generateRandomKey;

/**
 * @param data  representing the raw key bytes
 *
 * @returns a new instance if key is of appropriate length for AES256-GCM
 *          else returns nil.
 */
+ (nullable instancetype)keyWithData:(NSData *)data;

/// The raw key material
@property (nonatomic, readonly) NSData *keyData;

@end

#pragma mark -

@interface Cryptography : NSObject

typedef NS_ENUM(NSInteger, TSMACType) {
    TSHMACSHA256Truncated10Bytes = 2,
    TSHMACSHA256AttachementType = 3
};

+ (NSData *)generateRandomBytes:(NSUInteger)numberBytes;

+ (uint64_t)randomUInt64;

#pragma mark -

+ (void)seedRandom;

@end

NS_ASSUME_NONNULL_END
