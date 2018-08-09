#import <Foundation/Foundation.h>

@interface NSData (Util)

- (NSString *)encodedAsHexString;

- (const void *)bytesNotNull;

+ (NSData *)dataWithLength:(NSUInteger)length;

+ (NSData *)dataWithSingleByte:(uint8_t)value;

/// Decodes the data as a utf-8 string.
- (NSString *)decodedAsUtf8;

/// Decodes the data as an ascii string.
/// Throws when the data contains non-ascii character data (bytes larger than 127).
- (NSString *)decodedAsAscii;

/// Decodes the data as an ascii string.
/// Replaces any bad or non-printable characters with dots.
- (NSString *)decodedAsAsciiReplacingErrorsWithDots;

/// Finds the first index where the given sub data is present.
/// Returns nil if there is no such index.
- (NSNumber *)tryFindIndexOf:(NSData *)subData;

- (NSData *)skip:(NSUInteger)offset;

- (NSData *)take:(NSUInteger)takeCount;

- (NSData *)skipLast:(NSUInteger)skipLastCount;

- (NSData *)takeLast:(NSUInteger)takeLastCount;

/// Returns an NSData referencing a subrange of another NSData.
/// Modifying the original NSData will modify the result.
/// If the original is dealloced before the result, bad things happen to you.
- (NSData *)subdataVolatileWithRange:(NSRange)range;

/// Returns an NSData referencing the end of another NSData.
/// Modifying the original NSData will modify the result.
/// If the original is dealloced before the result, bad things happen to you.
- (NSData *)skipVolatile:(NSUInteger)offset;

/// Returns an NSData referencing the start of another NSData.
/// Modifying the original NSData will modify the result.
/// If the original is dealloced before the result, bad things happen to you.
- (NSData *)takeVolatile:(NSUInteger)takeCount;

/// Returns an NSData referencing the start of another NSData.
/// Modifying the original NSData will modify the result.
/// If the original is dealloced before the result, bad things happen to you.
- (NSData *)skipLastVolatile:(NSUInteger)skipLastCount;

/// Returns an NSData referencing the end of another NSData.
/// Modifying the original NSData will modify the result.
/// If the original is dealloced before the result, bad things happen to you.
- (NSData *)takeLastVolatile:(NSUInteger)takeLastCount;

- (uint8_t)uint8At:(NSUInteger)offset;

- (uint8_t)highUint4AtByteOffset:(NSUInteger)offset;

- (uint8_t)lowUint4AtByteOffset:(NSUInteger)offset;

- (NSString *)encodedAsBase64;

@end

@interface NSMutableData (Util)

- (void)replaceBytesStartingAt:(NSUInteger)offset withData:(NSData *)data;

- (void)setUint8At:(NSUInteger)offset to:(uint8_t)newValue;

@end
