//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSScrubbingLogFormatter.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSScrubbingLogFormatter

- (NSString *)formatLogMessage:(DDLogMessage *)logMessage
{
    NSString *logString = [super formatLogMessage:logMessage];
    NSRegularExpression *phoneRegex =
        [NSRegularExpression regularExpressionWithPattern:@"\\+\\d{7,12}(\\d{3})"
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:nil];

    logString = [phoneRegex stringByReplacingMatchesInString:logString
                                                     options:0
                                                       range:NSMakeRange(0, [logString length])
                                                withTemplate:@"[ REDACTED_PHONE_NUMBER:xxx$1 ]"];


    // We capture only the first two characters of the hex string for logging.
    NSRegularExpression *dataRegex =
        [NSRegularExpression regularExpressionWithPattern:@"<([\\da-f]{2})[\\da-f]{6}( [\\da-f]{8})*>"
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:nil];

    logString = [dataRegex stringByReplacingMatchesInString:logString
                                                    options:0
                                                      range:NSMakeRange(0, [logString length])
                                               withTemplate:@"[ REDACTED_DATA:$1... ]"];

    return logString;
}

@end

NS_ASSUME_NONNULL_END
