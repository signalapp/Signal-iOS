//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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
    const unsigned long kOneGigabyte = kOneMegabyte * kOneKilobyte;

    if (fileSize > kOneGigabyte * 1) {
        int gbSize = MIN(1, (int)round(fileSize / (CGFloat)kOneGigabyte));
        return [@[
            [formatter stringFromNumber:@(gbSize)],
            @"GB",
        ] componentsJoinedByString:@" "];
    } else if (fileSize > kOneMegabyte * 1) {
        int mbSize = MIN(1, (int)round(fileSize / (CGFloat)kOneMegabyte));
        return [@[
            [formatter stringFromNumber:@(mbSize)],
            @"MB",
        ] componentsJoinedByString:@" "];
    } else {
        int kbSize = MIN(1, (int)round(fileSize / (CGFloat)kOneKilobyte));
        return [@[
            [formatter stringFromNumber:@(kbSize)],
            @"KB",
        ] componentsJoinedByString:@" "];
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
