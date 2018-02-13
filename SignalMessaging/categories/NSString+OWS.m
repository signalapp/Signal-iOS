//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NSString+OWS.h"
#import "UIView+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSString (OWS)

- (NSString *)ows_stripped
{
    return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)rtlSafeAppend:(NSString *)string referenceView:(UIView *)referenceView
{
    OWSAssert(string);
    OWSAssert(referenceView);

    return [self rtlSafeAppend:string isRTL:referenceView.isRTL];
}

- (NSString *)rtlSafeAppend:(NSString *)string isRTL:(BOOL)isRTL
{
    OWSAssert(string);

    if (isRTL) {
        return [string stringByAppendingString:self];
    } else {
        return [self stringByAppendingString:string];
    }
}

- (NSString *)removeAllCharactersIn:(NSCharacterSet *)characterSet
{
    OWSAssert(characterSet);

    return [[self componentsSeparatedByCharactersInSet:characterSet] componentsJoinedByString:@""];
}

- (NSString *)digitsOnly
{
    return [self removeAllCharactersIn:[NSCharacterSet.decimalDigitCharacterSet invertedSet]];
}

@end

NS_ASSUME_NONNULL_END
