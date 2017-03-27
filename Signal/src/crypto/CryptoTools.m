//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "CryptoTools.h"

@implementation CryptoTools

+ (NSData *)generateSecureRandomData:(NSUInteger)length {
    NSMutableData *d = [NSMutableData dataWithLength:length];
    OSStatus status  = SecRandomCopyBytes(kSecRandomDefault, length, [d mutableBytes]);
    if (status != noErr) {
        [SecurityFailure raise:@"SecRandomCopyBytes failed"];
    }
    return [d copy];
}

@end
