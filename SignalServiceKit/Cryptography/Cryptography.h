//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Cryptography : NSObject

+ (NSData *)generateRandomBytes:(NSUInteger)numberBytes;

+ (uint64_t)randomUInt64;

#pragma mark -

+ (void)seedRandom;

@end

NS_ASSUME_NONNULL_END
