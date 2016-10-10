//  Created by Michael Kirk on 10/25/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSLogger.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSLogger

+ (void)verbose:(NSString *)logString
{
    DDLogVerbose(logString);
}

+ (void)debug:(NSString *)logString
{
    DDLogDebug(logString);
}

+ (void)info:(NSString *)logString
{
    DDLogInfo(logString);
}

+ (void)warn:(NSString *)logString
{
    DDLogWarn(logString);
}

+ (void)error:(NSString *)logString
{
    DDLogError(logString);
}

@end

NS_ASSUME_NONNULL_END
