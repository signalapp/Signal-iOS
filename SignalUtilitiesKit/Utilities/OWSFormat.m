//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSFormat.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSFormat

+ (NSString *)formatInt:(int)value
{
    static NSNumberFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSNumberFormatter new];
        formatter.numberStyle = NSNumberFormatterNoStyle;
    });
    return [formatter stringFromNumber:@(value)];
}

+ (NSString *)formatFileSize:(unsigned long)fileSize
{
    static NSNumberFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSNumberFormatter new];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
    });

    const unsigned long kOneKilobyte = 1024;
    const unsigned long kOneMegabyte = kOneKilobyte * kOneKilobyte;

    if (fileSize > kOneMegabyte) {
        return [[formatter stringFromNumber:@((double)lround(fileSize * 100 / (CGFloat)kOneMegabyte) / 100)]
            stringByAppendingString:@" MB"];
    } else if (fileSize > kOneKilobyte) {
        return [[formatter stringFromNumber:@((double)lround(fileSize * 100 / (CGFloat)kOneKilobyte) / 100)]
            stringByAppendingString:@" KB"];
    } else {
        return [NSString stringWithFormat:@"%lu Bytes", fileSize];
    }
}

@end

NS_ASSUME_NONNULL_END
