//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSScrubbingLogFormatter.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSScrubbingLogFormatter

- (NSRegularExpression *)phoneRegex
{
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *error;
        regex = [NSRegularExpression regularExpressionWithPattern:@"\\+\\d{7,12}(\\d{3})"
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:&error];
        if (error || !regex) {
            OWSFail(@"could not compile regular expression: %@", error);
        }
    });
    return regex;
}

- (NSRegularExpression *)dataRegex
{
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *error;
        regex = [NSRegularExpression regularExpressionWithPattern:@"<([\\da-f]{2})[\\da-f]{6}( [\\da-f]{8})*>"
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:&error];
        if (error || !regex) {
            OWSFail(@"could not compile regular expression: %@", error);
        }
    });
    return regex;
}

- (NSRegularExpression *)ipV4AddressRegex
{
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // NOTE: The group matches the last quad of the IPv4 address.
        NSError *error;
        regex = [NSRegularExpression regularExpressionWithPattern:@"\\d+\\.\\d+\\.\\d+\\.(\\d+)"
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:&error];
        if (error || !regex) {
            OWSFail(@"could not compile regular expression: %@", error);
        }
    });
    return regex;
}

- (NSString *__nullable)formatLogMessage:(DDLogMessage *)logMessage
{
    NSString *logString = [super formatLogMessage:logMessage];

    NSRegularExpression *phoneRegex = self.phoneRegex;
    logString = [phoneRegex stringByReplacingMatchesInString:logString
                                                     options:0
                                                       range:NSMakeRange(0, [logString length])
                                                withTemplate:@"[ REDACTED_PHONE_NUMBER:xxx$1 ]"];


    // We capture only the first two characters of the hex string for logging.
    // example log line: "Called someFunction with nsData: <01234567 89abcdef>"
    //  scrubbed output: "Called someFunction with nsData: [ REDACTED_DATA:01 ]"
    NSRegularExpression *dataRegex = self.dataRegex;
    logString = [dataRegex stringByReplacingMatchesInString:logString
                                                    options:0
                                                      range:NSMakeRange(0, [logString length])
                                               withTemplate:@"[ REDACTED_DATA:$1... ]"];

    NSRegularExpression *ipV4AddressRegex = self.ipV4AddressRegex;
    logString = [ipV4AddressRegex stringByReplacingMatchesInString:logString
                                                           options:0
                                                             range:NSMakeRange(0, [logString length])
                                                      withTemplate:@"[ REDACTED_IPV4_ADDRESS:...$1 ]"];

    return logString;
}

@end

NS_ASSUME_NONNULL_END
