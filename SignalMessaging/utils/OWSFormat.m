//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSFormat.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSFormat

+ (NSNumberFormatter *)defaultNumberFormatter
{
    static NSNumberFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSNumberFormatter new];
        formatter.numberStyle = NSNumberFormatterNoStyle;
    });
    return formatter;
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

    if (fileSize > kOneMegabyte * 10) {
        return [[formatter stringFromNumber:@((int)round(fileSize / (CGFloat)kOneMegabyte))]
            stringByAppendingString:@" MB"];
    } else if (fileSize > kOneKilobyte * 10) {
        return [[formatter stringFromNumber:@((int)round(fileSize / (CGFloat)kOneKilobyte))]
            stringByAppendingString:@" KB"];
    } else {
        return [NSString stringWithFormat:@"%lu Bytes", fileSize];
    }
}

+ (NSString *)formatDurationSeconds:(long)timeSeconds
{
    long seconds = timeSeconds % 60;
    long minutes = (timeSeconds / 60) % 60;
    long hours = timeSeconds / 3600;

    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", hours, minutes, seconds];
    } else {
        return [NSString stringWithFormat:@"%ld:%02ld", minutes, seconds];
    }
}

@end

NS_ASSUME_NONNULL_END
