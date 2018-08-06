//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NSData+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSData (OWS)

- (BOOL)ows_constantTimeIsEqualToData:(NSData *)other
{
    volatile UInt8 isEqual = 0;

    if (self.length != other.length) {
        return NO;
    }

    UInt8 *leftBytes = (UInt8 *)self.bytes;
    UInt8 *rightBytes = (UInt8 *)other.bytes;
    for (int i = 0; i < self.length; i++) {
        // rather than returning as soon as we find a discrepency, we compare the rest of
        // the byte stream to maintain a constant time comparison
        isEqual |= leftBytes[i] ^ rightBytes[i];
    }

    return isEqual == 0;
}

- (NSData *)dataByAppendingData:(NSData *)data
{
    NSMutableData *result = [self mutableCopy];
    [result appendData:data];
    return [result copy];
}

- (NSString *)hexadecimalString
{
    /* Returns hexadecimal string of NSData. Empty string if data is empty. */
    const unsigned char *dataBuffer = (const unsigned char *)[self bytes];
    if (!dataBuffer) {
        return @"";
    }

    NSUInteger dataLength = [self length];
    NSMutableString *hexString = [NSMutableString stringWithCapacity:(dataLength * 2)];

    for (NSUInteger i = 0; i < dataLength; ++i) {
        [hexString appendFormat:@"%02x", dataBuffer[i]];
    }
    return [hexString copy];
}

@end

NS_ASSUME_NONNULL_END
