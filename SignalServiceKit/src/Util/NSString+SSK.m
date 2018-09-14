//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NSString+SSK.h"
#import "iOSVersions.h"

NS_ASSUME_NONNULL_BEGIN

@interface UnicodeCodeRange : NSObject

@property (nonatomic) unichar first;
@property (nonatomic) unichar last;

@end

#pragma mark -

@implementation UnicodeCodeRange

+ (UnicodeCodeRange *)rangeWithStart:(unichar)first last:(unichar)last
{
    OWSAssertDebug(first <= last);

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
                    OWSLogError(@"Filtered unsafe Indic script.");
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
        if (range.length > 8) {
            // There are too many characters in this grapheme cluster.
            return YES;
        } else if (range.location != index || range.length < 1) {
            // This should never happen.
            OWSFailDebug(
                @"unexpected composed character sequence: %lu, %@", (unsigned long)index, NSStringFromRange(range));
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
        OWSFailDebug(@"could not compile regex: %@", error);
        return NO;
    }
    return [regex rangeOfFirstMatchInString:self options:0 range:NSMakeRange(0, self.length)].location != NSNotFound;
}

+ (NSString *)formatDurationSeconds:(uint32_t)durationSeconds useShortFormat:(BOOL)useShortFormat
{
    NSString *amountFormat;
    uint32_t duration;

    uint32_t secondsPerMinute = 60;
    uint32_t secondsPerHour = secondsPerMinute * 60;
    uint32_t secondsPerDay = secondsPerHour * 24;
    uint32_t secondsPerWeek = secondsPerDay * 7;

    if (durationSeconds < secondsPerMinute) { // XX Seconds
        if (useShortFormat) {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_SECONDS_SHORT_FORMAT",
                @"Label text below navbar button, embeds {{number of seconds}}. Must be very short, like 1 or 2 "
                @"characters, The space is intentionally omitted between the text and the embedded duration so that "
                @"we get, e.g. '5s' not '5 s'. See other *_TIME_AMOUNT strings");
        } else {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_SECONDS",
                @"{{number of seconds}} embedded in strings, e.g. 'Alice updated disappearing messages "
                @"expiration to {{5 seconds}}'. See other *_TIME_AMOUNT strings");
        }

        duration = durationSeconds;
    } else if (durationSeconds < secondsPerMinute * 1.5) { // 1 Minute
        if (useShortFormat) {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_MINUTES_SHORT_FORMAT",
                @"Label text below navbar button, embeds {{number of minutes}}. Must be very short, like 1 or 2 "
                @"characters, The space is intentionally omitted between the text and the embedded duration so that "
                @"we get, e.g. '5m' not '5 m'. See other *_TIME_AMOUNT strings");
        } else {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_SINGLE_MINUTE",
                @"{{1 minute}} embedded in strings, e.g. 'Alice updated disappearing messages "
                @"expiration to {{1 minute}}'. See other *_TIME_AMOUNT strings");
        }
        duration = durationSeconds / secondsPerMinute;
    } else if (durationSeconds < secondsPerHour) { // Multiple Minutes
        if (useShortFormat) {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_MINUTES_SHORT_FORMAT",
                @"Label text below navbar button, embeds {{number of minutes}}. Must be very short, like 1 or 2 "
                @"characters, The space is intentionally omitted between the text and the embedded duration so that "
                @"we get, e.g. '5m' not '5 m'. See other *_TIME_AMOUNT strings");
        } else {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_MINUTES",
                @"{{number of minutes}} embedded in strings, e.g. 'Alice updated disappearing messages "
                @"expiration to {{5 minutes}}'. See other *_TIME_AMOUNT strings");
        }

        duration = durationSeconds / secondsPerMinute;
    } else if (durationSeconds < secondsPerHour * 1.5) { // 1 Hour
        if (useShortFormat) {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_HOURS_SHORT_FORMAT",
                @"Label text below navbar button, embeds {{number of hours}}. Must be very short, like 1 or 2 "
                @"characters, The space is intentionally omitted between the text and the embedded duration so that "
                @"we get, e.g. '5h' not '5 h'. See other *_TIME_AMOUNT strings");
        } else {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_SINGLE_HOUR",
                @"{{1 hour}} embedded in strings, e.g. 'Alice updated disappearing messages "
                @"expiration to {{1 hour}}'. See other *_TIME_AMOUNT strings");
        }

        duration = durationSeconds / secondsPerHour;
    } else if (durationSeconds < secondsPerDay) { // Multiple Hours
        if (useShortFormat) {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_HOURS_SHORT_FORMAT",
                @"Label text below navbar button, embeds {{number of hours}}. Must be very short, like 1 or 2 "
                @"characters, The space is intentionally omitted between the text and the embedded duration so that "
                @"we get, e.g. '5h' not '5 h'. See other *_TIME_AMOUNT strings");
        } else {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_HOURS",
                @"{{number of hours}} embedded in strings, e.g. 'Alice updated disappearing messages "
                @"expiration to {{5 hours}}'. See other *_TIME_AMOUNT strings");
        }

        duration = durationSeconds / secondsPerHour;
    } else if (durationSeconds < secondsPerDay * 1.5) { // 1 Day
        if (useShortFormat) {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_DAYS_SHORT_FORMAT",
                @"Label text below navbar button, embeds {{number of days}}. Must be very short, like 1 or 2 "
                @"characters, The space is intentionally omitted between the text and the embedded duration so that "
                @"we get, e.g. '5d' not '5 d'. See other *_TIME_AMOUNT strings");
        } else {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_SINGLE_DAY",
                @"{{1 day}} embedded in strings, e.g. 'Alice updated disappearing messages "
                @"expiration to {{1 day}}'. See other *_TIME_AMOUNT strings");
        }

        duration = durationSeconds / secondsPerDay;
    } else if (durationSeconds < secondsPerWeek) { // Multiple Days
        if (useShortFormat) {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_DAYS_SHORT_FORMAT",
                @"Label text below navbar button, embeds {{number of days}}. Must be very short, like 1 or 2 "
                @"characters, The space is intentionally omitted between the text and the embedded duration so that "
                @"we get, e.g. '5d' not '5 d'. See other *_TIME_AMOUNT strings");
        } else {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_DAYS",
                @"{{number of days}} embedded in strings, e.g. 'Alice updated disappearing messages "
                @"expiration to {{5 days}}'. See other *_TIME_AMOUNT strings");
        }

        duration = durationSeconds / secondsPerDay;
    } else if (durationSeconds < secondsPerWeek * 1.5) { // 1 Week
        if (useShortFormat) {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_WEEKS_SHORT_FORMAT",
                @"Label text below navbar button, embeds {{number of weeks}}. Must be very short, like 1 or 2 "
                @"characters, The space is intentionally omitted between the text and the embedded duration so that "
                @"we get, e.g. '5w' not '5 w'. See other *_TIME_AMOUNT strings");
        } else {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_SINGLE_WEEK",
                @"{{1 week}} embedded in strings, e.g. 'Alice updated disappearing messages "
                @"expiration to {{1 week}}'. See other *_TIME_AMOUNT strings");
        }

        duration = durationSeconds / secondsPerWeek;
    } else { // Multiple weeks
        if (useShortFormat) {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_WEEKS_SHORT_FORMAT",
                @"Label text below navbar button, embeds {{number of weeks}}. Must be very short, like 1 or 2 "
                @"characters, The space is intentionally omitted between the text and the embedded duration so that "
                @"we get, e.g. '5w' not '5 w'. See other *_TIME_AMOUNT strings");
        } else {
            amountFormat = NSLocalizedString(@"TIME_AMOUNT_WEEKS",
                @"{{number of weeks}}, embedded in strings, e.g. 'Alice updated disappearing messages "
                @"expiration to {{5 weeks}}'. See other *_TIME_AMOUNT strings");
        }

        duration = durationSeconds / secondsPerWeek;
    }

    return [NSString stringWithFormat:amountFormat,
                     [NSNumberFormatter localizedStringFromNumber:@(duration) numberStyle:NSNumberFormatterNoStyle]];
}

@end

NS_ASSUME_NONNULL_END
