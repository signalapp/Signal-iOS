//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <CocoaLumberjack/CocoaLumberjack.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG
static const DDLogLevel ddLogLevel = DDLogLevelAll;
#else
static const DDLogLevel ddLogLevel = DDLogLevelInfo;
#endif

static inline BOOL ShouldLogFlag(DDLogFlag flag)
{
    return (ddLogLevel & flag) != 0;
}

static inline BOOL ShouldLogVerbose(void)
{
    return ddLogLevel >= DDLogLevelVerbose;
}

static inline BOOL ShouldLogDebug(void)
{
    return ddLogLevel >= DDLogLevelDebug;
}

static inline BOOL ShouldLogInfo(void)
{
    return ddLogLevel >= DDLogLevelInfo;
}

static inline BOOL ShouldLogWarning(void)
{
    return ddLogLevel >= DDLogLevelWarning;
}

static inline BOOL ShouldLogError(void)
{
    return ddLogLevel >= DDLogLevelError;
}

/// A helper method for `OWSLogIfEnabled`, which checks if a level should be logged.
void OWSLogUnconditionally(DDLogFlag flag,
    const char *file,
    BOOL shouldTrimFilePath,
    NSUInteger line,
    const char *function,
    NSString *format,
    ...) NS_FORMAT_FUNCTION(6, 7);

#define OWSLogIfEnabled(flg, fmt, ...)                                                                                 \
    do {                                                                                                               \
        if (ShouldLogFlag(flg))                                                                                        \
            OWSLogUnconditionally(flg, __FILE__, YES, __LINE__, __PRETTY_FUNCTION__, (fmt), ##__VA_ARGS__);            \
    } while (0)

#define OWSLogVerbose(fmt, ...) OWSLogIfEnabled(DDLogFlagVerbose, fmt, ##__VA_ARGS__)
#define OWSLogDebug(fmt, ...) OWSLogIfEnabled(DDLogFlagDebug, fmt, ##__VA_ARGS__)
#define OWSLogInfo(fmt, ...) OWSLogIfEnabled(DDLogFlagInfo, fmt, ##__VA_ARGS__)
#define OWSLogWarn(fmt, ...) OWSLogIfEnabled(DDLogFlagWarning, fmt, ##__VA_ARGS__)
#define OWSLogError(fmt, ...) OWSLogIfEnabled(DDLogFlagError, fmt, ##__VA_ARGS__)

#define OWSLogFlush()                                                                                                  \
    do {                                                                                                               \
        [DDLog flushLog];                                                                                              \
    } while (0)

NS_ASSUME_NONNULL_END
