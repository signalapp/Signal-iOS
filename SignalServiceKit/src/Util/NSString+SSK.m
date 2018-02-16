//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NSString+SSK.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSString (SSK)

- (NSString *)ows_stripped
{
    return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (BOOL)shouldFilterIndic
{
    static BOOL result = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        result = (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(11, 0) && !SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(11, 3));
    });
    return result;
}

// See: https://manishearth.github.io/blog/2018/02/15/picking-apart-the-crashing-ios-string/
- (NSString *)filterForIndicScripts
{
    if (!NSString.shouldFilterIndic) {
        return self;
    }

    NSMutableString *filteredForIndic = [NSMutableString new];
    for (NSUInteger i = 0; i < self.length; i++) {
        unichar c = [self characterAtIndex:i];
        if (c == 0x200C) {
            continue;
        }
        [filteredForIndic appendFormat:@"%C", c];
    }
    return [filteredForIndic copy];
}

- (NSString *)filterStringForDisplay
{
    return self.ows_stripped.filterForIndicScripts.filterForExcessiveDiacriticals;
}

- (NSString *)filterForExcessiveDiacriticals
{
    if (!self.hasExcessiveDiacriticals) {
        return self;
    }
    return [self stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:[NSLocale currentLocale]];
}

- (BOOL)hasExcessiveDiacriticals
{
    // discard any zalgo style text, by detecting maximum number of glyphs per character
    NSUInteger index = 0;
    while (index < self.length) {
        // Walk the grapheme clusters in the string.
        NSRange range = [self rangeOfComposedCharacterSequenceAtIndex:index];
        if (range.length > 4) {
            // There are too many characters in this grapheme cluster.
            return YES;
        } else if (range.location != index || range.length < 1) {
            // This should never happen.
            OWSFail(
                @"%@ unexpected composed character sequence: %zd, %@", self.logTag, index, NSStringFromRange(range));
            return YES;
        }
        index = range.location + range.length;
    }
    return NO;
}

- (BOOL)isValidE164
{
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^\\+\\d+$"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    if (error || !regex) {
        OWSFail(@"%@ could not compile regex: %@", self.logTag, error);
        return NO;
    }
    return [regex rangeOfFirstMatchInString:self options:0 range:NSMakeRange(0, self.length)].location != NSNotFound;
}

@end

NS_ASSUME_NONNULL_END
