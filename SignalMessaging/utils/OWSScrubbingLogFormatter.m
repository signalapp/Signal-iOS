//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSScrubbingLogFormatter.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSScrubbingLogFormatter

- (NSRegularExpression *)phoneRegex
{
    NSString *key = @"OWSScrubbingLogFormatter.phoneRegex";
    NSRegularExpression *_Nullable regex = NSThread.currentThread.threadDictionary[key];
    if (!regex) {
        NSError *error;
        regex = [NSRegularExpression regularExpressionWithPattern:@"\\+\\d{7,12}(\\d{3})"
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:&error];
        if (error || !regex) {
            OWSFail(@"%@ could not compile regular expression: %@", self.logTag, error);
        }
        NSThread.currentThread.threadDictionary[key] = regex;
    }
    return regex;
}

- (NSRegularExpression *)dataRegex
{
    NSString *key = @"OWSScrubbingLogFormatter.dataRegex";
    NSRegularExpression *_Nullable regex = NSThread.currentThread.threadDictionary[key];
    if (!regex) {
        NSError *error;
        regex = [NSRegularExpression regularExpressionWithPattern:@"<([\\da-f]{2})[\\da-f]{6}( [\\da-f]{8})*>"
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:&error];
        if (error || !regex) {
            OWSFail(@"%@ could not compile regular expression: %@", self.logTag, error);
        }
        NSThread.currentThread.threadDictionary[key] = regex;
    }
    return regex;
}

- (NSRegularExpression *)ipAddressRegex
{
    NSString *key = @"OWSScrubbingLogFormatter.ipAddressRegex";
    NSRegularExpression *_Nullable regex = NSThread.currentThread.threadDictionary[key];
    if (!regex) {
        // Match IPv4 and IPv6 addresses.
        //
        // NOTE: the second group matches the last "quad/hex?" of the IPv4/IPv6 address.
        NSError *error;
        regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d+\\.\\d+\\.)?\\d+\\.\\d+\\.\\d+\\.(\\d+)"
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:&error];
        if (error || !regex) {
            OWSFail(@"%@ could not compile regular expression: %@", self.logTag, error);
        }
        NSThread.currentThread.threadDictionary[key] = regex;
    }
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

    NSRegularExpression *ipAddressRegex = self.ipAddressRegex;
    logString = [ipAddressRegex stringByReplacingMatchesInString:logString
                                                         options:0
                                                           range:NSMakeRange(0, [logString length])
                                                    withTemplate:@"[ REDACTED_IP_ADDRESS:...$2 ]"];

    return logString;
}

@end

NS_ASSUME_NONNULL_END
