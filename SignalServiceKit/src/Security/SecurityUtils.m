//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SecurityUtils.h"
#import <Curve25519Kit/Randomness.h>

@implementation SecurityUtils

+ (NSData *)generateRandomBytes:(NSUInteger)length
{
    return [Randomness generateRandomBytes:length];
}

@end
