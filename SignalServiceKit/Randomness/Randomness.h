//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Randomness : NSObject

/**
 *  Generates a given number of cryptographically secure bytes using SecRandomCopyBytes.
 *
 *  @param numberBytes The number of bytes to be generated.
 *
 *  @return Random Bytes.
 */

+ (NSData *)generateRandomBytes:(int)numberBytes;

@end

NS_ASSUME_NONNULL_END
