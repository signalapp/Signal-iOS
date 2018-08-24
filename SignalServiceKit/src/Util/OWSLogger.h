//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

static inline BOOL ShouldLogVerbose()
{
    return ddLogLevel >= DDLogLevelVerbose;
}

static inline BOOL ShouldLogDebug()
{
    return ddLogLevel >= DDLogLevelDebug;
}

static inline BOOL ShouldLogInfo()
{
    return ddLogLevel >= DDLogLevelInfo;
}

static inline BOOL ShouldLogWarning()
{
    return ddLogLevel >= DDLogLevelWarning;
}

static inline BOOL ShouldLogError()
{
    return ddLogLevel >= DDLogLevelError;
}

/**
 * A minimal DDLog wrapper for swift.
 */
@interface OWSLogger : NSObject

+ (void)verbose:(NSString *)logString;
+ (void)debug:(NSString *)logString;
+ (void)info:(NSString *)logString;
+ (void)warn:(NSString *)logString;
+ (void)error:(NSString *)logString;

+ (void)flush;

@end

NS_ASSUME_NONNULL_END
