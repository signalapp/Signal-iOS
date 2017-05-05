//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NumberUtil.h"
#import "StringUtil.h"

@implementation NSString (Util)

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
- (NSDictionary *)decodedAsJsonIntoDictionary {
    NSError *jsonParseError = nil;
    id parsedJson = [NSJSONSerialization JSONObjectWithData:self.encodedAsUtf8 options:0 error:&jsonParseError];
    checkOperationDescribe(jsonParseError == nil,
                           ([NSString stringWithFormat:@"Json parse error: %@, on json: %@", jsonParseError, self]));
    checkOperationDescribe([parsedJson isKindOfClass:NSDictionary.class], @"Unexpected json data");
    return parsedJson;
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
