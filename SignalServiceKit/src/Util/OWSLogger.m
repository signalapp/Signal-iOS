//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSLogger.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSLogger

+ (void)verbose:(OWSLogBlock)logBlock;
{
    DDLogVerbose(@"%@", logBlock());
}

+ (void)debug:(OWSLogBlock)logBlock;
{
    DDLogDebug(@"%@", logBlock());
}

+ (void)info:(OWSLogBlock)logBlock;
{
    DDLogInfo(@"%@", logBlock());
}

+ (void)warn:(OWSLogBlock)logBlock;
{
    DDLogWarn(@"%@", logBlock());
}

+ (void)error:(OWSLogBlock)logBlock;
{
    DDLogError(@"%@", logBlock());
}

+ (void)flush
{
    [DDLog flushLog];
}

@end

NS_ASSUME_NONNULL_END
