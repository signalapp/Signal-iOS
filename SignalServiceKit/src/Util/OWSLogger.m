//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSLogger.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSLogger

+ (void)verbose:(NSString *)logString;
{
    DDLogVerbose(@"%@", logString);
}

+ (void)debug:(NSString *)logString;
{
    DDLogDebug(@"%@", logString);
}

+ (void)info:(NSString *)logString;
{
    DDLogInfo(@"%@", logString);
}

+ (void)warn:(NSString *)logString;
{
    DDLogWarn(@"%@", logString);
}

+ (void)error:(NSString *)logString;
{
    DDLogError(@"%@", logString);
}

+ (void)flush
{
    [DDLog flushLog];
}

@end

NS_ASSUME_NONNULL_END
