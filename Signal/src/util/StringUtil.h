#import <Foundation/Foundation.h>

@interface NSString (Util)

/// The utf-8 encoding of the string's text.
- (NSData *)encodedAsUtf8;
/// The ascii encoding of the string's text.
/// Throws when the string contains non-ascii characters.
- (NSData *)encodedAsAscii;
- (NSRegularExpression *)toRegularExpression;
- (NSString *)withMatchesAgainst:(NSRegularExpression *)regex replacedBy:(NSString *)replacement;
- (bool)containsAnyMatches:(NSRegularExpression *)regex;
- (NSString *)withPrefixRemovedElseNull:(NSString *)prefix;
- (NSData *)decodedAsJsonIntoData;
- (NSDictionary *)decodedAsJsonIntoDictionary;
- (NSData *)decodedAsHexString;
- (NSData *)decodedAsSpaceSeparatedHexString;
- (NSData *)decodedAsBase64Data;
- (NSNumber *)tryParseAsDecimalNumber;
- (NSNumber *)tryParseAsUnsignedInteger;
- (NSString *)removeAllCharactersIn:(NSCharacterSet *)characterSet;
- (NSString *)digitsOnly;
- (NSString *)withCharactersInRange:(NSRange)range replacedBy:(NSString *)substring;

@end
