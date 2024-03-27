//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "NSString+SSK.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSString (SSK)

- (NSString *)filterAsE164
{
    const NSUInteger maxLength = 256;
    NSUInteger inputLength = MIN(maxLength, self.length);
    unichar inputChars[inputLength];
    [self getCharacters:(unichar *)inputChars range:NSMakeRange(0, inputLength)];

    unichar outputChars[inputLength];
    NSUInteger outputLength = 0;
    for (NSUInteger i = 0; i < inputLength; i++) {
        unichar c = inputChars[i];
        if (c >= '0' && c <= '9') {
            outputChars[outputLength++] = c;
        } else if (outputLength == 0 && c == '+') {
            outputChars[outputLength++] = c;
        }
    }

    return [NSString stringWithCharacters:outputChars length:outputLength];
}

- (NSString *)substringBeforeRange:(NSRange)range
{
    return [self substringToIndex:range.location];
}

- (NSString *)substringAfterRange:(NSRange)range
{
    return [self substringFromIndex:range.location + range.length];
}

- (NSString *_Nullable)stringOrNil
{
    return self;
}

@end

#pragma mark -

@implementation NSMutableAttributedString (SSK)

- (void)setAttributes:(NSDictionary<NSAttributedStringKey, id> *)attributes forSubstring:(NSString *)substring
{
    if (substring.length < 1) {
        OWSFailDebug(@"Invalid substring.");
        return;
    }
    NSRange range = [self.string rangeOfString:substring];
    if (range.location == NSNotFound) {
        OWSFailDebug(@"Substring not found.");
        return;
    }
    [self setAttributes:attributes range:range];
}

@end

#pragma mark -

@implementation NSNull(NSStringSSK)

- (NSString *_Nullable)stringOrNil
{
    return nil;
}

@end

NS_ASSUME_NONNULL_END
