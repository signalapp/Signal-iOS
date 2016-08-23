//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSOutgoingSyncMessage

- (BOOL)shouldSyncTranscript
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
