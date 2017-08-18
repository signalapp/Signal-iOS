//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSContactOffersInteraction.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactOffersInteraction ()

//@property (atomic) BOOL hasMoreUnseenMessages;

@end

#pragma mark -

@implementation OWSContactOffersInteraction

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread
//                   hasMoreUnseenMessages:(BOOL)hasMoreUnseenMessages
//    missingUnseenSafetyNumberChangeCount:(NSUInteger)missingUnseenSafetyNumberChangeCount
{
    self = [super initWithTimestamp:timestamp inThread:thread];

    if (!self) {
        return self;
    }

    //    _hasMoreUnseenMessages = hasMoreUnseenMessages;
    //    _missingUnseenSafetyNumberChangeCount = missingUnseenSafetyNumberChangeCount;

    return self;
}

- (BOOL)shouldUseReceiptDateForSorting
{
    // Use the timestamp, not the "received at" timestamp to sort,
    // since we're creating these interactions after the fact and back-dating them.
    return NO;
}

- (BOOL)isDynamicInteraction
{
    return YES;
}

@end

NS_ASSUME_NONNULL_END
