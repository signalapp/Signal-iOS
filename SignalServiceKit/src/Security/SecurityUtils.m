//
//  SecurityUtils.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 28/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "SecurityUtils.h"

@implementation SecurityUtils

+ (NSData *)generateRandomBytes:(int)numberBytes {
    NSMutableData *randomBytes = [NSMutableData dataWithLength:(NSUInteger)numberBytes];
    int err                    = 0;
    err                        = SecRandomCopyBytes(kSecRandomDefault, (size_t)numberBytes, [randomBytes mutableBytes]);
    if (err != noErr) {
        @throw [NSException exceptionWithName:@"random problem" reason:@"problem generating the random " userInfo:nil];
    }
    return randomBytes;
}

@end
