//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSInteraction.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSUnreadIndicatorInteraction : TSInteraction

@property (atomic, readonly) BOOL hasMoreUnseenMessages;

@property (atomic, readonly) NSUInteger missingUnseenSafetyNumberChangeCount;

- (instancetype)initInteractionWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread NS_UNAVAILABLE;

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initUnreadIndicatorWithTimestamp:(uint64_t)timestamp
                                          thread:(TSThread *)thread
                           hasMoreUnseenMessages:(BOOL)hasMoreUnseenMessages
            missingUnseenSafetyNumberChangeCount:(NSUInteger)missingUnseenSafetyNumberChangeCount
    NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
