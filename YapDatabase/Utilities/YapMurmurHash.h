#import <Foundation/Foundation.h>

/**
 * MurmurHash2 was written by Austin Appleby, and is placed in the public domain.
 * http://code.google.com/p/smhasher
**/

#ifndef YapDatabase_YapMurmurHash_h
#define YapDatabase_YapMurmurHash_h
	
NSUInteger YapMurmurHash2(NSUInteger hash1, NSUInteger hash2);

NSUInteger YapMurmurHash3(NSUInteger hash1, NSUInteger hash2, NSUInteger hash3);

NSUInteger YapMurmurHashData(NSData *data);

int32_t YapMurmurHashData_32(NSData *data);
int64_t YapMurmurHashData_64(NSData *data);

#endif
