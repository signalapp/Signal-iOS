//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NSData+OWSConstantTimeCompare.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSData (OWSConstantTimeCompare)

- (BOOL)ows_constantTimeIsEqualToData:(NSData *)other
{
    BOOL isEqual = YES;

    if (self.length != other.length) {
        return NO;
    }

    UInt8 *leftBytes = (UInt8 *)self.bytes;
    UInt8 *rightBytes = (UInt8 *)other.bytes;
    for (int i = 0; i < self.length; i++) {
        // rather than returning as soon as we find a discrepency, we compare the rest of
        // the byte stream to maintain a constant time comparison
        isEqual = isEqual && (leftBytes[i] == rightBytes[i]);
    }

    return isEqual;
}

@end

NS_ASSUME_NONNULL_END
