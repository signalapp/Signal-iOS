//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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
                                                          options:0
                                                            error:&error];
        if (error || !regex) {
            OWSFail(@"could not compile regular expression: %@", error);
        }
    });
    return regex;
}

- (NSRegularExpression *)uuidRegex
{
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Example: AF112388-9F3D-4EBA-A321-CCE01BA2C85D
        NSError *error;
        regex =
            [NSRegularExpression regularExpressionWithPattern:
                                     @"[\\da-f]{8}\\-[\\da-f]{4}\\-[\\da-f]{4}\\-[\\da-f]{4}\\-[\\da-f]{9}([\\da-f]{3})"
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
        regex = [NSRegularExpression regularExpressionWithPattern:@"<([\\da-f]{2})[\\da-f]{0,6}( [\\da-f]{2,8})*>"
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:&error];
        if (error || !regex) {
            OWSFail(@"could not compile regular expression: %@", error);
        }
    });
    return regex;
}

- (NSRegularExpression *)ios13DataRegex
{
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *error;
        regex = [NSRegularExpression
            regularExpressionWithPattern:@"\\{length = \\d+, bytes = 0x([\\da-f]{2})[\\.\\da-f ]*\\}"
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

- (NSRegularExpression *)longHexRegex
{
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Any hex string of 14 chars (7 bytes) or more.
        // Example: A321CCE01BA2C85D
        NSError *error;
        regex = [NSRegularExpression regularExpressionWithPattern:@"[\\da-f]{11,}([\\da-f]{3})"
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

    NSRegularExpression *uuidRegex = self.uuidRegex;
    logString = [uuidRegex stringByReplacingMatchesInString:logString
                                                    options:0
                                                      range:NSMakeRange(0, [logString length])
                                               withTemplate:@"[ REDACTED_UUID:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxx$1 ]"];

    // We capture only the first two characters of the hex string for logging.
    // example log line: "Called someFunction with nsData: <01234567 89abcdef>"
    //  scrubbed output: "Called someFunction with nsData: [ REDACTED_DATA:01 ]"
    NSRegularExpression *dataRegex = self.dataRegex;
    logString = [dataRegex stringByReplacingMatchesInString:logString
                                                    options:0
                                                      range:NSMakeRange(0, [logString length])
                                               withTemplate:@"[ REDACTED_DATA:$1... ]"];

    // On iOS 13, when built with the 13 SDK, NSData's description has changed
    // and needs to be scrubbed specifically.
    // example log line: "Called someFunction with nsData: {length = 8, bytes = 0x0123456789abcdef}"
    //  scrubbed output: "Called someFunction with nsData: [ REDACTED_DATA:96 ]"
    NSRegularExpression *ios13DataRegex = self.ios13DataRegex;
    logString = [ios13DataRegex stringByReplacingMatchesInString:logString
                                                         options:0
                                                           range:NSMakeRange(0, [logString length])
                                                    withTemplate:@"[ REDACTED_DATA:$1... ]"];

    NSRegularExpression *ipV4AddressRegex = self.ipV4AddressRegex;
    logString = [ipV4AddressRegex stringByReplacingMatchesInString:logString
                                                           options:0
                                                             range:NSMakeRange(0, [logString length])
                                                      withTemplate:@"[ REDACTED_IPV4_ADDRESS:...$1 ]"];

    NSRegularExpression *longHexRegex = self.longHexRegex;
    logString = [longHexRegex stringByReplacingMatchesInString:logString
                                                       options:0
                                                         range:NSMakeRange(0, [logString length])
                                                  withTemplate:@"[ REDACTED_HEX:...$1 ]"];

    return logString;
}

@end

NS_ASSUME_NONNULL_END
