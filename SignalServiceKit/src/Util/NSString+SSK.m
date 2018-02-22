//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NSString+SSK.h"

NS_ASSUME_NONNULL_BEGIN

@interface UnicodeCodeRange : NSObject

@property (nonatomic) unichar first;
@property (nonatomic) unichar last;

@end

#pragma mark -

@implementation UnicodeCodeRange

+ (UnicodeCodeRange *)rangeWithStart:(unichar)first last:(unichar)last
{
    OWSAssert(first <= last);

    UnicodeCodeRange *range = [UnicodeCodeRange new];
    range.first = first;
    range.last = last;
    return range;
}

- (NSComparisonResult)compare:(UnicodeCodeRange *)other
{

    return self.first > other.first;
}

@end

#pragma mark -

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

+ (BOOL)isIndicVowel:(unichar)c
{
    static NSArray<UnicodeCodeRange *> *ranges;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // From:
        //    https://unicode.org/charts/PDF/U0C00.pdf
        //    https://unicode.org/charts/PDF/U0980.pdf
        //    https://unicode.org/charts/PDF/U0900.pdf
        ranges = [@[
            // Telugu:
            [UnicodeCodeRange rangeWithStart:0xC05 last:0xC14],
            [UnicodeCodeRange rangeWithStart:0xC3E last:0xC4C],
            [UnicodeCodeRange rangeWithStart:0xC60 last:0xC63],
            // Bengali
            [UnicodeCodeRange rangeWithStart:0x985 last:0x994],
            [UnicodeCodeRange rangeWithStart:0x9BE last:0x9C8],
            [UnicodeCodeRange rangeWithStart:0x9CB last:0x9CC],
            [UnicodeCodeRange rangeWithStart:0x9E0 last:0x9E3],
            // Devanagari
            [UnicodeCodeRange rangeWithStart:0x904 last:0x914],
            [UnicodeCodeRange rangeWithStart:0x93A last:0x93B],
            [UnicodeCodeRange rangeWithStart:0x93E last:0x94C],
            [UnicodeCodeRange rangeWithStart:0x94E last:0x94F],
            [UnicodeCodeRange rangeWithStart:0x955 last:0x957],
            [UnicodeCodeRange rangeWithStart:0x960 last:0x963],
            [UnicodeCodeRange rangeWithStart:0x972 last:0x977],
        ] sortedArrayUsingSelector:@selector(compare:)];
    });

    for (UnicodeCodeRange *range in ranges) {
        if (c < range.first) {
            // For perf, we can take advantage of the fact that the
            // ranges are sorted to exit early if the character lies
            // before the current range.
            return NO;
        }
        if (range.first <= c && c <= range.last) {
            return YES;
        }
    }
    return NO;
}

+ (NSCharacterSet *)problematicCharacterSetForIndicScript
{
    static NSCharacterSet *characterSet;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        characterSet = [NSCharacterSet characterSetWithCharactersInString:@"\u200C"];
    });

    return characterSet;
}

// See: https://manishearth.github.io/blog/2018/02/15/picking-apart-the-crashing-ios-string/
- (NSString *)filterForIndicScripts
{
    if (!NSString.shouldFilterIndic) {
        return self;
    }

    if ([self rangeOfCharacterFromSet:[[self class] problematicCharacterSetForIndicScript]].location == NSNotFound) {
        return self;
    }

    NSMutableString *filteredForIndic = [NSMutableString new];
    for (NSUInteger index = 0; index < self.length; index++) {
        unichar c = [self characterAtIndex:index];
        if (c == 0x200C) {
            NSUInteger nextIndex = index + 1;
            if (nextIndex < self.length) {
                unichar next = [self characterAtIndex:nextIndex];
                if ([NSString isIndicVowel:next]) {
                    // Discard ZWNJ (zero-width non-joiner) whenever we find a ZWNJ
                    // followed by an Indic (Telugu, Bengali, Devanagari) vowel
                    // and replace it with 0xFFFD, the Unicode "replacement character."
                    [filteredForIndic appendFormat:@"\uFFFD"];
                    DDLogError(@"%@ Filtered unsafe Indic script.", self.logTag);
                    // Then discard the vowel too.
                    index++;
                    continue;
                }
            }
        }
        [filteredForIndic appendFormat:@"%C", c];
    }
    return [filteredForIndic copy];
}

+ (NSCharacterSet *)unsafeFilenameCharacterSet
{
    static NSCharacterSet *characterSet;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 0x202D and 0x202E are the unicode ordering letters
        // and can be used to control the rendering of text.
        // They could be used to construct misleading attachment
        // filenames that appear to have a different file extension,
        // for example.
        characterSet = [NSCharacterSet characterSetWithCharactersInString:@"\u202D\u202E"];
    });

    return characterSet;
}

- (NSString *)filterUnsafeFilenameCharacters
{
    NSCharacterSet *unsafeCharacterSet = [[self class] unsafeFilenameCharacterSet];
    NSRange range = [self rangeOfCharacterFromSet:unsafeCharacterSet];
    if (range.location == NSNotFound) {
        return self;
    }
    NSMutableString *filtered = [NSMutableString new];
    NSString *remainder = [self copy];
    while (range.location != NSNotFound) {
        if (range.location > 0) {
            [filtered appendString:[remainder substringToIndex:range.location]];
        }
        // The "replacement" code point.
        [filtered appendString:@"\uFFFD"];
        remainder = [remainder substringFromIndex:range.location + range.length];
        range = [remainder rangeOfCharacterFromSet:unsafeCharacterSet];
    }
    [filtered appendString:remainder];
    return filtered;
}

- (NSString *)filterStringForDisplay
{
    return self.ows_stripped.filterForIndicScripts.filterForExcessiveDiacriticals;
}

- (NSString *)filterFilename
{
    return self.ows_stripped.filterForIndicScripts.filterForExcessiveDiacriticals.filterUnsafeFilenameCharacters;
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
