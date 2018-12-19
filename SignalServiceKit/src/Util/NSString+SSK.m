//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NSString+SSK.h"
#import "AppContext.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSString (SSK)

- (NSString *)ows_stripped
{
    return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)rtlSafeAppend:(NSString *)string
{
    OWSAssertDebug(string);

    if (CurrentAppContext().isRTL) {
        return [string stringByAppendingString:self];
    } else {
        return [self stringByAppendingString:string];
    }
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
