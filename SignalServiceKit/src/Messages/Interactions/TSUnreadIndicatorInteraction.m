//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSUnreadIndicatorInteraction.h"

NS_ASSUME_NONNULL_BEGIN

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
@implementation TSUnreadIndicatorInteraction
#pragma clang diagnostic pop

// --- CODE GENERATION MARKER

// clang-format off

- (instancetype)initWithUniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(unsigned long long)receivedAtTimestamp
                          sortId:(unsigned long long)sortId
                       timestamp:(unsigned long long)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
{
    self = [super initWithUniqueId:uniqueId
               receivedAtTimestamp:receivedAtTimestamp
                            sortId:sortId
                         timestamp:timestamp
                    uniqueThreadId:uniqueThreadId];

    if (!self) {
        return self;
    }

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
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

- (OWSInteractionType)interactionType
{
    return OWSInteractionType_Unknown;
}

@end

NS_ASSUME_NONNULL_END
