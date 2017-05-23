//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSUnreadIndicatorInteraction.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSUnreadIndicatorInteraction

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread
{
    self = [super initWithTimestamp:timestamp
                           inThread:thread
                        messageBody:nil
                      attachmentIds:@[]
                   expiresInSeconds:0
                    expireStartedAt:0];

    if (!self) {
        return self;
    }

    return self;
}

- (nullable NSDate *)receiptDateForSorting
{
    // Always use date, since we're creating these interactions after the fact
    // and back-dating them.
    //
    // By default [TSMessage receiptDateForSorting] will prefer to use receivedAtDate
    // which is not back-dated.
    return self.date;
}

- (BOOL)isDynamicInteraction
{
    return YES;
}

@end

NS_ASSUME_NONNULL_END
