//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSScrubbingLogFormatter.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSScrubbingLogFormatter

- (NSString *)formatLogMessage:(DDLogMessage *)logMessage
{
    NSString *string = [super formatLogMessage:logMessage];
    NSRegularExpression *phoneRegex =
        [NSRegularExpression regularExpressionWithPattern:@"\\+\\d{7,12}(\\d{3})"
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:nil];
    NSString *filteredString = [phoneRegex stringByReplacingMatchesInString:string
                                                                    options:0
                                                                      range:NSMakeRange(0, [string length])
                                                               withTemplate:@"[ REDACTED_PHONE_NUMBER:xxx$1 ]"];

    return filteredString;
}

@end

NS_ASSUME_NONNULL_END
