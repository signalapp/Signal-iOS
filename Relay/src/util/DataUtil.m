#import "Constraints.h"
#import "DataUtil.h"

@implementation NSData (Util)
- (const void *)bytesNotNull {
    // note: this storage location is static, not auto, so its lifetime does not end
    // (also, by virtue of being const, there are no threading/entrancy issues)
    static const int SafeNonNullPointerToStaticStorageLocation[1];

    if (self.length == 0) {
        return SafeNonNullPointerToStaticStorageLocation;
    } else {
        ows_require([self bytes] != nil);
        return [self bytes];
    }
}
+ (NSData *)dataWithLength:(NSUInteger)length {
    return [NSMutableData dataWithLength:length];
}

+ (NSData *)dataWithSingleByte:(uint8_t)value {
    return [NSData dataWithBytes:&value length:sizeof(value)];
}
- (NSNumber *)tryFindIndexOf:(NSData *)subData {
    ows_require(subData != nil);
    if (subData.length > self.length)
        return nil;

    NSUInteger subDataLength = subData.length;
    NSUInteger excessLength  = self.length - subDataLength;

    const uint8_t *selfBytes    = [self bytes];
    const uint8_t *subDataBytes = [subData bytes];
    for (NSUInteger i = 0; i <= excessLength; i++) {
        if (memcmp(selfBytes + i, subDataBytes, subDataLength) == 0) {
            return @(i);
        }
    }
    return nil;
}
- (NSString *)encodedAsHexString {
    if (![self bytes])
        return @"";

    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < self.length; ++i)
        [result appendString:[NSString stringWithFormat:@"%02x", [self uint8At:i]]];

    return result;
}
- (NSString *)decodedAsUtf8 {
    // workaround for empty data having nil bytes
    if (self.length == 0)
        return @"";

    [NSString stringWithUTF8String:[self bytes]];
    NSString *result = [[NSString alloc] initWithData:self encoding:NSUTF8StringEncoding];
    checkOperationDescribe(result != nil, @"Invalid UTF8 data.");
    return result;
}
- (NSString *)decodedAsAscii {
    // workaround for empty data having nil bytes
    if (self.length == 0)
        return @"";
    // workaround for initWithData not enforcing the fact that NSASCIIStringEncoding means strict 7-bit
    for (NSUInteger i = 0; i < self.length; i++) {
        checkOperationDescribe(([self uint8At:i] & 0x80) == 0, @"Invalid ascii data.");
    }

    NSString *result = [[NSString alloc] initWithData:self encoding:NSASCIIStringEncoding];
    checkOperationDescribe(result != nil, @"Invalid ascii data.");
    return result;
}
- (NSString *)decodedAsAsciiReplacingErrorsWithDots {
    const int MinPrintableChar = ' ';
    const int MaxPrintableChar = '~';

    NSMutableData *d = [NSMutableData dataWithLength:self.length];
    for (NSUInteger i = 0; i < self.length; i++) {
        uint8_t v = [self uint8At:i];
        if (v < MinPrintableChar || v > MaxPrintableChar)
            v = '.';
        [d setUint8At:i to:v];
    }
    return [d decodedAsAscii];
}

- (NSData *)skip:(NSUInteger)offset {
    ows_require(offset <= self.length);
    return [self subdataWithRange:NSMakeRange(offset, self.length - offset)];
}
- (NSData *)take:(NSUInteger)takeCount {
    ows_require(takeCount <= self.length);
    return [self subdataWithRange:NSMakeRange(0, takeCount)];
}
- (NSData *)skipLast:(NSUInteger)skipLastCount {
    ows_require(skipLastCount <= self.length);
    return [self subdataWithRange:NSMakeRange(0, self.length - skipLastCount)];
}
- (NSData *)takeLast:(NSUInteger)takeLastCount {
    ows_require(takeLastCount <= self.length);
    return [self subdataWithRange:NSMakeRange(self.length - takeLastCount, takeLastCount)];
}

- (NSData *)subdataVolatileWithRange:(NSRange)range {
    NSUInteger length = self.length;
    ows_require(range.location <= length);
    ows_require(range.length <= length);
    ows_require(range.location + range.length <= length);

    return [NSData dataWithBytesNoCopy:(uint8_t *)[self bytes] + range.location length:range.length freeWhenDone:NO];
}
- (NSData *)skipVolatile:(NSUInteger)offset {
    ows_require(offset <= self.length);
    return [self subdataVolatileWithRange:NSMakeRange(offset, self.length - offset)];
}
- (NSData *)takeVolatile:(NSUInteger)takeCount {
    ows_require(takeCount <= self.length);
    return [self subdataVolatileWithRange:NSMakeRange(0, takeCount)];
}
- (NSData *)skipLastVolatile:(NSUInteger)skipLastCount {
    ows_require(skipLastCount <= self.length);
    return [self subdataVolatileWithRange:NSMakeRange(0, self.length - skipLastCount)];
}
- (NSData *)takeLastVolatile:(NSUInteger)takeLastCount {
    ows_require(takeLastCount <= self.length);
    return [self subdataVolatileWithRange:NSMakeRange(self.length - takeLastCount, takeLastCount)];
}

- (uint8_t)highUint4AtByteOffset:(NSUInteger)offset {
    return [self uint8At:offset] >> 4;
}
- (uint8_t)lowUint4AtByteOffset:(NSUInteger)offset {
    return [self uint8At:offset] & 0xF;
}
- (uint8_t)uint8At:(NSUInteger)offset {
    ows_require(offset < self.length);
    return ((const uint8_t *)[self bytes])[offset];
}
- (const uint8_t *)constPtrToUint8At:(NSUInteger)offset {
    return ((uint8_t *)[self bytes]) + offset;
}
- (NSString *)encodedAsBase64 {
    const NSUInteger BitsPerBase64Word = 6;
    const NSUInteger BitsPerByte       = 8;
    const uint8_t Base64Chars[]        = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    NSUInteger byteCount       = self.length;
    NSUInteger bitCount        = byteCount * BitsPerByte;
    NSUInteger base64WordCount = bitCount / BitsPerBase64Word;
    if (base64WordCount * BitsPerBase64Word < bitCount)
        base64WordCount += 1;

    // base 256 to to base 2
    bool bits[bitCount];
    for (NSUInteger i = 0; i < byteCount; i++) {
        for (NSUInteger j = 0; j < BitsPerByte; j++) {
            bits[i * BitsPerByte + BitsPerByte - 1 - j] = (([self uint8At:i] >> j) & 1) != 0;
        }
    }

    // base 2 to base 64
    uint8_t base64Words[base64WordCount];
    for (NSUInteger i = 0; i < base64WordCount; i++) {
        base64Words[i] = 0;
        for (NSUInteger j = 0; j < BitsPerBase64Word; j++) {
            NSUInteger offset = i * BitsPerBase64Word + BitsPerBase64Word - 1 - j;
            if (offset >= bitCount)
                continue; // default to 0
            if (bits[offset])
                base64Words[i] |= 1 << j;
        }
    }

    // base 64 to ASCII data
    NSUInteger paddingCount  = bitCount % 3;
    NSMutableData *asciiData = [NSMutableData dataWithLength:base64WordCount + paddingCount];
    for (NSUInteger i = 0; i < base64WordCount; i++) {
        [asciiData setUint8At:i to:Base64Chars[base64Words[i]]];
    }
    for (NSUInteger i = 0; i < paddingCount; i++) {
        [asciiData setUint8At:i + base64WordCount to:'='];
    }

    return [asciiData decodedAsAscii];
}
@end

@implementation NSMutableData (Util)
- (void)setUint8At:(NSUInteger)offset to:(uint8_t)newValue {
    ows_require(offset < self.length);
    ((uint8_t *)[self mutableBytes])[offset] = newValue;
}
- (void)replaceBytesStartingAt:(NSUInteger)offset withData:(NSData *)data {
    ows_require(data != nil);
    ows_require(offset + data.length <= self.length);
    [self replaceBytesInRange:NSMakeRange(offset, data.length) withBytes:[data bytes]];
}
@end
