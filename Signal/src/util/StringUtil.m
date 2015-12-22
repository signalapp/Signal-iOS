#import "Constraints.h"
#import "DataUtil.h"
#import "NumberUtil.h"
#import "StringUtil.h"

@implementation NSString (Util)
- (NSData *)decodedAsHexString {
    ows_require(self.length % 2 == 0);

    NSUInteger n = self.length / 2;
    uint8_t result[n];
    for (NSUInteger i = 0; i < n; i++) {
        unsigned int r;
        NSScanner *scanner = [NSScanner scannerWithString:[self substringWithRange:NSMakeRange(i * 2, 2)]];
        checkOperation([scanner scanHexInt:&r]);
        checkOperation(r < 256);
        result[i] = (uint8_t)r;
    }
    return [NSData dataWithBytes:result length:sizeof(result)];
}
- (NSData *)decodedAsSpaceSeparatedHexString {
    NSArray *hexComponents = [self componentsSeparatedByString:@" "];

    NSMutableData *result = [NSMutableData new];
    for (NSString *component in hexComponents) {
        unsigned int r;
        NSScanner *scanner = [NSScanner scannerWithString:component];
        checkOperation([scanner scanHexInt:&r]);
        checkOperation(r < 256);
        [result appendData:[NSData dataWithSingleByte:(uint8_t)r]];
    }

    return result;
}
- (NSData *)encodedAsUtf8 {
    NSData *result = [self dataUsingEncoding:NSUTF8StringEncoding];
    checkOperationDescribe(result != nil, @"Not a UTF8 string.");
    return result;
}
- (NSData *)encodedAsAscii {
    NSData *result = [self dataUsingEncoding:NSASCIIStringEncoding];
    checkOperationDescribe(result != nil, @"Not an ascii string.");
    return result;
}
- (NSRegularExpression *)toRegularExpression {
    NSError *regexInitError = NULL;
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:self options:0 error:&regexInitError];
    checkOperation(regex != nil && regexInitError == NULL);
    return regex;
}
- (NSString *)withMatchesAgainst:(NSRegularExpression *)regex replacedBy:(NSString *)replacement {
    ows_require(regex != nil);
    ows_require(replacement != nil);
    NSMutableString *m = self.mutableCopy;
    [regex replaceMatchesInString:m options:0 range:NSMakeRange(0, m.length) withTemplate:replacement];
    return m;
}
- (bool)containsAnyMatches:(NSRegularExpression *)regex {
    ows_require(regex != nil);
    return [regex numberOfMatchesInString:self options:0 range:NSMakeRange(0, self.length)] > 0;
}
- (NSString *)withPrefixRemovedElseNull:(NSString *)prefix {
    ows_require(prefix != nil);
    if (prefix.length > 0 && ![self hasPrefix:prefix])
        return nil;
    return [self substringFromIndex:prefix.length];
}
- (NSData *)decodedAsJsonIntoData {
    NSError *jsonParseError = nil;
    id parsedJson = [NSJSONSerialization dataWithJSONObject:self.encodedAsUtf8 options:0 error:&jsonParseError];
    checkOperationDescribe(jsonParseError == nil, ([NSString stringWithFormat:@"Invalid json: %@", self]));
    checkOperationDescribe([parsedJson isKindOfClass:NSData.class], @"Unexpected json data");
    return parsedJson;
}
- (NSDictionary *)decodedAsJsonIntoDictionary {
    NSError *jsonParseError = nil;
    id parsedJson = [NSJSONSerialization JSONObjectWithData:self.encodedAsUtf8 options:0 error:&jsonParseError];
    checkOperationDescribe(jsonParseError == nil,
                           ([NSString stringWithFormat:@"Json parse error: %@, on json: %@", jsonParseError, self]));
    checkOperationDescribe([parsedJson isKindOfClass:NSDictionary.class], @"Unexpected json data");
    return parsedJson;
}
- (NSData *)decodedAsBase64Data {
    const NSUInteger BitsPerBase64Word = 6;
    const NSUInteger BitsPerByte       = 8;
    const uint8_t Base64Chars[]        = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    uint8_t CharToValueMap[256];
    for (NSUInteger i = 0; i < 256; i++) {
        CharToValueMap[i] = 255;
    }
    for (uint8_t i = 0; i < 64; i++) {
        CharToValueMap[Base64Chars[i]] = i;
    }

    // Determine amount of information (based on length and padding)
    NSUInteger paddingCount = 0;
    while (paddingCount < 2 && paddingCount < self.length - 1 &&
           [self characterAtIndex:self.length - paddingCount - 1] == '=') {
        paddingCount += 1;
    }
    NSUInteger base64WordCount = self.length - paddingCount;
    NSUInteger bitCount        = self.length * BitsPerBase64Word - paddingCount * BitsPerByte;
    NSUInteger byteCount       = bitCount / BitsPerByte;
    checkOperation(bitCount % BitsPerByte == 0);

    // ASCII to base 64
    NSData *asciiData = self.encodedAsAscii;
    uint8_t base64Words[base64WordCount];
    for (NSUInteger i = 0; i < base64WordCount; i++) {
        base64Words[i] = CharToValueMap[[asciiData uint8At:i]];
        ows_require(base64Words[i] < 64);
    }

    // base 64 to base 2
    bool bits[bitCount];
    for (NSUInteger i = 0; i < base64WordCount; i++) {
        for (NSUInteger j = 0; j < BitsPerBase64Word; j++) {
            NSUInteger k = (i + 1) * BitsPerBase64Word - 1 - j;
            if (k >= bitCount)
                continue; // may occur due to padding
            bits[k] = ((base64Words[i] >> j) & 1) != 0;
        }
    }

    // base 2 to base 256
    uint8_t bytes[byteCount];
    for (NSUInteger i = 0; i < byteCount; i++) {
        bytes[i] = 0;
        for (NSUInteger j = 0; j < BitsPerByte; j++) {
            NSUInteger k = (i + 1) * BitsPerByte - 1 - j;
            if (bits[k])
                bytes[i] |= 1 << j;
        }
    }

    return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}
- (NSNumber *)tryParseAsDecimalNumber {
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];

    // NSNumberFormatter.numberFromString is good at noticing bad inputs, but loses precision for large values
    // NSDecimalNumber.decimalNumberWithString has perfect precision, but lets bad inputs through sometimes (e.g.
    // "88ffhih" -> 88)
    // We use both to get both accuracy and detection of bad inputs
    if ([formatter numberFromString:self] == nil) {
        return nil;
    }
    return [NSDecimalNumber decimalNumberWithString:self];
}
- (NSNumber *)tryParseAsUnsignedInteger {
    NSNumber *value = [self tryParseAsDecimalNumber];
    return value.hasUnsignedIntegerValue ? value : nil;
}
- (NSString *)removeAllCharactersIn:(NSCharacterSet *)characterSet {
    ows_require(characterSet != nil);
    return [[self componentsSeparatedByCharactersInSet:characterSet] componentsJoinedByString:@""];
}
- (NSString *)digitsOnly {
    return [self removeAllCharactersIn:[NSCharacterSet.decimalDigitCharacterSet invertedSet]];
}
- (NSString *)withCharactersInRange:(NSRange)range replacedBy:(NSString *)substring {
    NSMutableString *result = self.mutableCopy;
    [result replaceCharactersInRange:range withString:substring];
    return result;
}

@end
