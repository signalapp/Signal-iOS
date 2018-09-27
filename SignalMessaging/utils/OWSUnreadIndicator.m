//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSUnreadIndicator.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSUnreadIndicator

- (instancetype)initWithFirstUnseenSortId:(uint64_t)firstUnseenSortId
                    hasMoreUnseenMessages:(BOOL)hasMoreUnseenMessages
     missingUnseenSafetyNumberChangeCount:(NSUInteger)missingUnseenSafetyNumberChangeCount
                  unreadIndicatorPosition:(NSInteger)unreadIndicatorPosition
{
    self = [super init];

    if (!self) {
        return self;
    }

    _firstUnseenSortId = firstUnseenSortId;
    _hasMoreUnseenMessages = hasMoreUnseenMessages;
    _missingUnseenSafetyNumberChangeCount = missingUnseenSafetyNumberChangeCount;
    _unreadIndicatorPosition = unreadIndicatorPosition;

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
    return (self.firstUnseenSortId == other.firstUnseenSortId
        && self.hasMoreUnseenMessages == other.hasMoreUnseenMessages
        && self.missingUnseenSafetyNumberChangeCount == other.missingUnseenSafetyNumberChangeCount
        && self.unreadIndicatorPosition == other.unreadIndicatorPosition);
}

@end

NS_ASSUME_NONNULL_END
