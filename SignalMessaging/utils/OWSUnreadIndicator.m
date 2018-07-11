//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSUnreadIndicator.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSUnreadIndicator

- (instancetype)initUnreadIndicatorWithTimestamp:(uint64_t)timestamp
                           hasMoreUnseenMessages:(BOOL)hasMoreUnseenMessages
            missingUnseenSafetyNumberChangeCount:(NSUInteger)missingUnseenSafetyNumberChangeCount
                         unreadIndicatorPosition:(NSInteger)unreadIndicatorPosition
                 firstUnseenInteractionTimestamp:(uint64_t)firstUnseenInteractionTimestamp
{
    self = [super init];

    if (!self) {
        return self;
    }

    _timestamp = timestamp;
    _hasMoreUnseenMessages = hasMoreUnseenMessages;
    _missingUnseenSafetyNumberChangeCount = missingUnseenSafetyNumberChangeCount;
    _unreadIndicatorPosition = unreadIndicatorPosition;
    _firstUnseenInteractionTimestamp = firstUnseenInteractionTimestamp;

    return self;
}

- (BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[OWSUnreadIndicator class]]) {
        return NO;
    }

    OWSUnreadIndicator *other = object;
    return (self.timestamp == other.timestamp && self.hasMoreUnseenMessages == other.hasMoreUnseenMessages
        && self.missingUnseenSafetyNumberChangeCount == other.missingUnseenSafetyNumberChangeCount
        && self.unreadIndicatorPosition == other.unreadIndicatorPosition);
}

@end

NS_ASSUME_NONNULL_END
