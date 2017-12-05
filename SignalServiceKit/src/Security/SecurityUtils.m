//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SecurityUtils.h"

@implementation SecurityUtils

+ (NSData *)generateRandomBytes:(NSUInteger)length
{
    NSMutableData *d = [NSMutableData dataWithLength:length];
    OSStatus status = SecRandomCopyBytes(kSecRandomDefault, length, [d mutableBytes]);
    if (status != noErr) {
        [SecurityFailure raise:@"SecRandomCopyBytes failed"];
    }
    return [d copy];
}

@end
