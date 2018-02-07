//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSIncomingMessage;
@class TSOutgoingMessage;
@class TSQuotedMessage;
@class TSThread;
@class YapDatabaseReadWriteTransaction;

@interface OWSMessageUtils : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)sharedManager;

- (NSUInteger)unreadMessagesCount;
- (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread;
- (NSUInteger)unreadMessagesInThread:(TSThread *)thread;

- (void)updateApplicationBadgeCount;

+ (nullable TSQuotedMessage *)quotedMessageForIncomingMessage:(TSIncomingMessage *)message
                                                  transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (nullable TSQuotedMessage *)quotedMessageForOutgoingMessage:(TSOutgoingMessage *)message
                                                  transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
