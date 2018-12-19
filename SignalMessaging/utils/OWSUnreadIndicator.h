//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSUnreadIndicator : NSObject

@property (nonatomic, readonly) BOOL hasMoreUnseenMessages;

@property (nonatomic, readonly) NSUInteger missingUnseenSafetyNumberChangeCount;

// The sortId of the oldest unseen message.
//
// Once we enter messages view, we mark all messages read, so we need
// a snapshot of what the first unread message was when we entered the
// view so that we can call ensureDynamicInteractionsForThread:...
// repeatedly. The unread indicator should continue to show up until
// it has been cleared, at which point hideUnreadMessagesIndicator is
// YES in ensureDynamicInteractionsForThread:...
@property (nonatomic, readonly) uint64_t firstUnseenSortId;

// The index of the unseen indicator, counting from the _end_ of the conversation
// history.
//
// This is used by MessageViewController to increase the
// range size of the mappings (the load window of the conversation)
// to include the unread indicator.
@property (nonatomic, readonly) NSInteger unreadIndicatorPosition;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithFirstUnseenSortId:(uint64_t)firstUnseenSortId
                    hasMoreUnseenMessages:(BOOL)hasMoreUnseenMessages
     missingUnseenSafetyNumberChangeCount:(NSUInteger)missingUnseenSafetyNumberChangeCount
                  unreadIndicatorPosition:(NSInteger)unreadIndicatorPosition NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
