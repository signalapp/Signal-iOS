#import <Foundation/Foundation.h>

#pragma once

NS_ASSUME_NONNULL_BEGIN

/**
 * MurmurHash2 was written by Austin Appleby, and is placed in the public domain.
 * http://code.google.com/p/smhasher
**/

NSUInteger YapMurmurHash2(NSUInteger hash1, NSUInteger hash2);

NSUInteger YapMurmurHash3(NSUInteger hash1, NSUInteger hash2, NSUInteger hash3);

NSUInteger YapMurmurHashData(NSData *data);

uint32_t YapMurmurHashData_32(NSData * data);
uint64_t YapMurmurHashData_64(NSData * data);

NS_ASSUME_NONNULL_END
