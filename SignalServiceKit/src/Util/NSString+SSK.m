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
- (NSString *)filterStringForDisplay
{
    NSString *stripped = self.ows_stripped;

    if (!NSString.shouldFilterIndic) {
        return stripped;
    }
    NSMutableString *result = [NSMutableString new];
    for (NSUInteger i = 0; i < stripped.length; i++) {
        unichar c = [stripped characterAtIndex:i];
        if (c == 0x200C) {
            continue;
        }
        [result appendFormat:@"%C", c];
    }
    return [result copy];
}

@end

NS_ASSUME_NONNULL_END
