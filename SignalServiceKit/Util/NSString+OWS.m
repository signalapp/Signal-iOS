//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "NSString+OWS.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

static void *kNSString_SSK_needsSanitization = &kNSString_SSK_needsSanitization;
static void *kNSString_SSK_sanitizedCounterpart = &kNSString_SSK_sanitizedCounterpart;
static unichar bidiLeftToRightIsolate = 0x2066;
static unichar bidiRightToLeftIsolate = 0x2067;
static unichar bidiFirstStrongIsolate = 0x2068;
static unichar bidiLeftToRightEmbedding = 0x202A;
static unichar bidiRightToLeftEmbedding = 0x202B;
static unichar bidiLeftToRightOverride = 0x202D;
static unichar bidiRightToLeftOverride = 0x202E;
static unichar bidiPopDirectionalFormatting = 0x202C;
static unichar bidiPopDirectionalIsolate = 0x2069;

@implementation NSString (OWS)

+ (NSCharacterSet *)nonPrintingCharacterSet
{
    static NSCharacterSet *result = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *characterSet = NSCharacterSet.whitespaceAndNewlineCharacterSet.mutableCopy;
        [characterSet formUnionWithCharacterSet:NSCharacterSet.controlCharacterSet];
        [characterSet formUnionWithCharacterSet:[self bidiControlCharacterSet]];
        // Left-to-right and Right-to-left marks.
        [characterSet addCharactersInString:@"\u200E\u200f"];
        result = [characterSet copy];
    });
    return result;
}

+ (NSCharacterSet *)bidiControlCharacterSet
{
    static NSCharacterSet *result = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *characterSet = [NSMutableCharacterSet new];
        [characterSet addCharactersInString:[NSString stringWithFormat:@"%C%C%C%C%C%C%C%C%C",
                                                      bidiLeftToRightIsolate,
                                                      bidiRightToLeftIsolate,
                                                      bidiFirstStrongIsolate,
                                                      bidiLeftToRightEmbedding,
                                                      bidiRightToLeftEmbedding,
                                                      bidiLeftToRightOverride,
                                                      bidiRightToLeftOverride,
                                                      bidiPopDirectionalFormatting,
                                                      bidiPopDirectionalIsolate]];
        result = [characterSet copy];
    });
    return result;
}

- (NSString *)ows_stripped
{
    if ([self stringByTrimmingCharactersInSet:[NSString nonPrintingCharacterSet]].length < 1) {
        // If string has no printing characters, consider it empty.
        return @"";
    }
    return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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

- (NSString *)filterSubstringForDisplay
{
    // We don't want to strip a substring before filtering.
    return self.sanitized.ensureBalancedBidiControlCharacters;
}

- (NSString *)filterStringForDisplay
{
    return self.ows_stripped.filterSubstringForDisplay;
}

- (NSString *)filterFilename
{
    return self.ows_stripped.sanitized.filterUnsafeFilenameCharacters;
}

- (NSString *)withoutBidiControlCharacters
{
    return [self stringByTrimmingCharactersInSet:[NSString bidiControlCharacterSet]];
}

- (NSString *)ensureBalancedBidiControlCharacters
{
    NSInteger isolateStartsCount = 0;
    NSInteger isolatePopCount = 0;
    NSInteger formattingStartsCount = 0;
    NSInteger formattingPopCount = 0;

    for (NSUInteger index = 0; index < self.length; index++) {
        unichar c = [self characterAtIndex:index];
        if (c == bidiLeftToRightIsolate || c == bidiRightToLeftIsolate || c == bidiFirstStrongIsolate) {
            isolateStartsCount++;
        } else if (c == bidiPopDirectionalIsolate) {
            isolatePopCount++;
        } else if (c == bidiLeftToRightEmbedding || c == bidiRightToLeftEmbedding || c == bidiLeftToRightOverride
            || c == bidiRightToLeftOverride) {
            formattingStartsCount++;
        } else if (c == bidiPopDirectionalFormatting) {
            formattingPopCount++;
        }
    }

    if (isolateStartsCount == 0 && isolatePopCount == 0 && formattingStartsCount == 0 && formattingPopCount == 0) {
        return self;
    }

    NSMutableString *balancedString = [NSMutableString new];


    // If we have too many isolate pops, prepend FSI to balance
    while (isolatePopCount > isolateStartsCount) {
        [balancedString appendFormat:@"%C", bidiFirstStrongIsolate];
        isolateStartsCount++;
    }

    // If we have too many formatting pops, prepend LRE to balance
    while (formattingPopCount > formattingStartsCount) {
        [balancedString appendFormat:@"%C", bidiLeftToRightEmbedding];
        formattingStartsCount++;
    }

    [balancedString appendString:self];

    // If we have too many formatting starts, append PDF to balance
    while (formattingStartsCount > formattingPopCount) {
        [balancedString appendFormat:@"%C", bidiPopDirectionalFormatting];
        formattingPopCount++;
    }

    // If we have too many isolate starts, append PDI to balance
    while (isolateStartsCount > isolatePopCount) {
        [balancedString appendFormat:@"%C", bidiPopDirectionalIsolate];
        isolatePopCount++;
    }

    return [balancedString copy];
}

- (NSString *)stringByPrependingCharacter:(unichar)character
{
    return [NSString stringWithFormat:@"%C%@", character, self];
}

- (NSString *)stringByAppendingCharacter:(unichar)character
{
    return [self stringByAppendingFormat:@"%C", character];
}

- (NSString *)bidirectionallyBalancedAndIsolated
{
    if (self.length > 1) {
        unichar firstChar = [self characterAtIndex:0];
        unichar lastChar = [self characterAtIndex:self.length - 1];

        // We're already isolated, nothing to do here.
        if (firstChar == bidiFirstStrongIsolate && lastChar == bidiPopDirectionalIsolate) {
            return self;
        }
    }

    return [NSString stringWithFormat:@"%C%@%C",
                     bidiFirstStrongIsolate,
                     self.ensureBalancedBidiControlCharacters,
                     bidiPopDirectionalIsolate];
}

- (NSString *)sanitized
{
    NSNumber *cachedNeedsSanitization = objc_getAssociatedObject(self, kNSString_SSK_needsSanitization);
    if (cachedNeedsSanitization != nil) {
        if (cachedNeedsSanitization.boolValue) {
            return objc_getAssociatedObject(self, kNSString_SSK_sanitizedCounterpart) ?: self;
        } else {
            return self;
        }
    }

    StringSanitizer *sanitizer = [[StringSanitizer alloc] initWithString:self];
    const BOOL needsSanitization = sanitizer.needsSanitization;
    objc_setAssociatedObject(self, kNSString_SSK_needsSanitization, @(needsSanitization), OBJC_ASSOCIATION_COPY);
    if (!needsSanitization) {
        return self;
    }
    NSString *sanitized = sanitizer.sanitized;
    objc_setAssociatedObject(self, kNSString_SSK_sanitizedCounterpart, sanitized, OBJC_ASSOCIATION_COPY);
    return sanitized;
}

+ (NSRegularExpression *)anyASCIIRegex
{
    static dispatch_once_t onceToken;
    static NSRegularExpression *regex;
    dispatch_once(&onceToken, ^{
        NSError *error;
        regex = [NSRegularExpression regularExpressionWithPattern:@"[\x00-\x7F]+" options:0 error:&error];
        if (error || !regex) {
            // crash! it's not clear how to proceed safely, and this regex should never fail.
            OWSFail(@"could not compile regex: %@", error);
        }
    });

    return regex;
}

+ (NSRegularExpression *)onlyASCIIRegex
{
    static dispatch_once_t onceToken;
    static NSRegularExpression *regex;
    dispatch_once(&onceToken, ^{
        NSError *error;
        regex = [NSRegularExpression regularExpressionWithPattern:@"^[\x00-\x7F]*$" options:0 error:&error];
        if (error || !regex) {
            // crash! it's not clear how to proceed safely, and this regex should never fail.
            OWSFail(@"could not compile regex: %@", error);
        }
    });

    return regex;
}


- (BOOL)isOnlyASCII
{
    return
        [self.class.onlyASCIIRegex rangeOfFirstMatchInString:self options:0 range:NSMakeRange(0, self.length)].location
        != NSNotFound;
}

- (BOOL)hasAnyASCII
{
    return
        [self.class.anyASCIIRegex rangeOfFirstMatchInString:self options:0 range:NSMakeRange(0, self.length)].location
        != NSNotFound;
}

- (NSString *)removeAllCharactersIn:(NSCharacterSet *)characterSet
{
    OWSAssertDebug(characterSet);

    return [[self componentsSeparatedByCharactersInSet:characterSet] componentsJoinedByString:@""];
}

- (NSString *)digitsOnly
{
    return [self removeAllCharactersIn:[NSCharacterSet.decimalDigitCharacterSet invertedSet]];
}

@end

NS_ASSUME_NONNULL_END
