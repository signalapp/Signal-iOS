//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kOversizeTextMessageSizeThreshold = 2 * 1024;

BOOL IsUsingProductionService()
{
#ifdef USING_PRODUCTION_SERVICE
    return YES;
#else
    return NO;
#endif
}

NS_ASSUME_NONNULL_END
