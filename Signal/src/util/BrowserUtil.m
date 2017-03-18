//
//  Copyright © 2017 Open Whisper Systems. All rights reserved.
//

#import "BrowserUtil.h"

NS_ASSUME_NONNULL_BEGIN

@implementation BrowserUtil

+ (NSArray *)detectInstalledBrowserNames {
    NSArray *detected = @[ @"Safari" ];
    if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"googlechromes://whispersystems.org"]]) {
        detected = [detected arrayByAddingObject:@"Chrome"];
    }
    return detected;
}

+ (NSDictionary *)schemesForBrowser:(NSString *)browserName {
    if ([browserName isEqualToString:@"Safari"]) {
        return @{
            @"http": @"http",
            @"https": @"https",
        };
    } else if ([browserName isEqualToString:@"Chrome"]) {
        return @{
            @"http": @"googlechrome",
            @"https": @"googlechromes",
        };
    }
    return @{};
}

@end

NS_ASSUME_NONNULL_END
