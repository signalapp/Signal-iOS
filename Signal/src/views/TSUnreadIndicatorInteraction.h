//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSInteraction.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSUnreadIndicatorInteraction : TSInteraction

@property (atomic, readonly) BOOL hasMoreUnseenMessages;

@property (atomic, readonly) NSUInteger missingUnseenSafetyNumberChangeCount;

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                                  thread:(TSThread *)thread
                   hasMoreUnseenMessages:(BOOL)hasMoreUnseenMessages
    missingUnseenSafetyNumberChangeCount:(NSUInteger)missingUnseenSafetyNumberChangeCount NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
