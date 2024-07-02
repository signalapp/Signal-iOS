//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSLogs.h"
#import <stdatomic.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSLogger

static void logUnconditionally(
    DDLogFlag flag, const char *file, BOOL shouldTrimFilePath, NSUInteger line, const char *function, NSString *message)
{
    OWSCPrecondition(ShouldLogFlag(flag));
    NSString *fileObj = [NSString stringWithFormat:@"%s", file];
    fileObj = shouldTrimFilePath ? fileObj.lastPathComponent : fileObj;
    DDLogMessage *logMessage = [[DDLogMessage alloc] initWithMessage:message
                                                               level:ddLogLevel
                                                                flag:flag
                                                             context:0
                                                                file:fileObj
                                                            function:[NSString stringWithFormat:@"%s", function]
                                                                line:line
                                                                 tag:nil
                                                             options:0
                                                           timestamp:nil];
    [DDLog log:YES message:logMessage];
}

void OWSLogUnconditionally(DDLogFlag flag,
    const char *file,
    BOOL shouldTrimFilePath,
    NSUInteger line,
    const char *function,
    NSString *format,
    ...)
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    logUnconditionally(flag, file, shouldTrimFilePath, line, function, message);
}

static void _logShim(DDLogFlag flag, NSString *logString)
{
    if (!ShouldLogFlag(flag)) {
        return;
    }
    logUnconditionally(flag, "", NO, 0, "", logString);
}

+ (void)verbose:(NSString *)logString
{
    _logShim(DDLogFlagVerbose, logString);
}

+ (void)debug:(NSString *)logString
{
    _logShim(DDLogFlagDebug, logString);
}

+ (void)info:(NSString *)logString
{
    _logShim(DDLogFlagInfo, logString);
}

+ (void)warn:(NSString *)logString
{
    _logShim(DDLogFlagWarning, logString);
}

+ (void)error:(NSString *)logString
{
    _logShim(DDLogFlagError, logString);
}

@end

NS_ASSUME_NONNULL_END
