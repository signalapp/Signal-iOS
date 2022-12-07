//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "PhoneNumberUtil.h"
#import "FunctionalUtil.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <libPhoneNumber_iOS/NBPhoneNumber.h>

NS_ASSUME_NONNULL_BEGIN

@implementation PhoneNumberUtil

- (instancetype)init {
    self = [super init];

    if (self) {
        _phoneNumberUtilWrapper = [PhoneNumberUtilWrapper new];
    }

    OWSSingletonAssert();

    return self;
}

- (NSString *)probableCountryCodeForCallingCode:(NSString *)callingCode
{
    OWSAssertDebug(callingCode.length > 0);

    NSArray<NSString *> *countryCodes = [self countryCodesFromCallingCode:callingCode];
    return (countryCodes.count > 0 ? countryCodes[0] : nil);
}

// black  magic
+ (NSUInteger)translateCursorPosition:(NSUInteger)offset
                                 from:(NSString *)source
                                   to:(NSString *)target
                    stickingRightward:(bool)preferHigh {
    OWSAssertDebug(source != nil);
    OWSAssertDebug(target != nil);
    OWSAssertDebug(offset <= source.length);
    if (source == nil || target == nil || offset > source.length) {
        return 0;
    }

    NSUInteger n = source.length;
    NSUInteger m = target.length;

    int moves[n + 1][m + 1];
    {
        // Wagner-Fischer algorithm for computing edit distance, with a tweaks:
        // - Tracks best moves at each location, to allow reconstruction of edit path
        // - Does not allow substitutions
        // - Over-values digits relative to other characters, so they're "harder" to delete or insert
        const int DIGIT_VALUE = 10;
        NSUInteger scores[n + 1][m + 1];
        moves[0][0]  = 0; // (match) move up and left
        scores[0][0] = 0;
        for (NSUInteger i = 1; i <= n; i++) {
            scores[i][0] = i;
            moves[i][0]  = -1; // (deletion) move left
        }
        for (NSUInteger j = 1; j <= m; j++) {
            scores[0][j] = j;
            moves[0][j]  = +1; // (insertion) move up
        }

        NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
        for (NSUInteger i = 1; i <= n; i++) {
            unichar c1    = [source characterAtIndex:i - 1];
            bool isDigit1 = [digits characterIsMember:c1];
            for (NSUInteger j = 1; j <= m; j++) {
                unichar c2    = [target characterAtIndex:j - 1];
                bool isDigit2 = [digits characterIsMember:c2];
                if (c1 == c2) {
                    scores[i][j] = scores[i - 1][j - 1];
                    moves[i][j]  = 0; // move up-and-left
                } else {
                    NSUInteger del = scores[i - 1][j] + (isDigit1 ? DIGIT_VALUE : 1);
                    NSUInteger ins = scores[i][j - 1] + (isDigit2 ? DIGIT_VALUE : 1);
                    bool isDel     = del < ins;
                    scores[i][j]   = isDel ? del : ins;
                    moves[i][j]    = isDel ? -1 : +1;
                }
            }
        }
    }

    // Backtrack to find desired corresponding offset
    for (NSUInteger i = n, j = m;; i -= 1) {
        if (i == offset && preferHigh)
            return j; // early exit
        while (moves[i][j] == +1)
            j -= 1; // zip upward
        if (i == offset)
            return j; // late exit
        if (moves[i][j] == 0)
            j -= 1;
    }
}

+ (nullable NBPhoneNumber *)getExampleNumberForType:(NSString *)regionCode
                                               type:(NBEPhoneNumberType)type
                                  nbPhoneNumberUtil:(NBPhoneNumberUtil *)nbPhoneNumberUtil
{
    NSError *error;
    NBPhoneNumber *_Nullable nbPhoneNumber = [nbPhoneNumberUtil getExampleNumberForType:regionCode type:type error:&error];
    if (error != nil) {
        OWSFailDebug(@"Error: %@", error);
    }
    return nbPhoneNumber;
}

@end

NS_ASSUME_NONNULL_END
