//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

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
