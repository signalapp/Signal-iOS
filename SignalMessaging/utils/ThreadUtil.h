//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSBlockingManager;
@class OWSContactShare;
@class OWSContactsManager;
@class OWSMessageSender;
@class OWSQuotedReplyModel;
@class SignalAttachment;
@class TSContactThread;
@class TSInteraction;
@class TSOutgoingMessage;
@class TSThread;
@class YapDatabaseConnection;
@class YapDatabaseReadTransaction;

@interface ThreadDynamicInteractions : NSObject

// If there are unseen messages in the thread, this is the index
// of the unseen indicator, counting from the _end_ of the conversation
// history.
//
// This is used by MessageViewController to increase the
// range size of the mappings (the load window of the conversation)
// to include the unread indicator.
@property (nonatomic, nullable, readonly) NSNumber *unreadIndicatorPosition;

// If there are unseen messages in the thread, this is the timestamp
// of the oldest unseen message.
//
// Once we enter messages view, we mark all messages read, so we need
// a snapshot of what the first unread message was when we entered the
// view so that we can call ensureDynamicInteractionsForThread:...
// repeatedly. The unread indicator should continue to show up until
// it has been cleared, at which point hideUnreadMessagesIndicator is
// YES in ensureDynamicInteractionsForThread:...
@property (nonatomic, nullable, readonly) NSNumber *firstUnseenInteractionTimestamp;

@property (nonatomic, readonly) BOOL hasMoreUnseenMessages;

- (void)clearUnreadIndicatorState;

@end

#pragma mark -

@interface ThreadUtil : NSObject

+ (TSOutgoingMessage *)sendMessageWithText:(NSString *)text
                                  inThread:(TSThread *)thread
                          quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                             messageSender:(OWSMessageSender *)messageSender
                                   success:(void (^)(void))successHandler
                                   failure:(void (^)(NSError *error))failureHandler;

+ (TSOutgoingMessage *)sendMessageWithText:(NSString *)text
                                  inThread:(TSThread *)thread
                          quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                             messageSender:(OWSMessageSender *)messageSender;

+ (TSOutgoingMessage *)sendMessageWithAttachment:(SignalAttachment *)attachment
                                        inThread:(TSThread *)thread
                                quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                   messageSender:(OWSMessageSender *)messageSender
                                      completion:(void (^_Nullable)(NSError *_Nullable error))completion;

// We only should set ignoreErrors in debug or test code.
+ (TSOutgoingMessage *)sendMessageWithAttachment:(SignalAttachment *)attachment
                                        inThread:(TSThread *)thread
                                quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                   messageSender:(OWSMessageSender *)messageSender
                                    ignoreErrors:(BOOL)ignoreErrors
                                      completion:(void (^_Nullable)(NSError *_Nullable error))completion;

+ (TSOutgoingMessage *)sendMessageWithContactShare:(OWSContactShare *)contactShare
                                          inThread:(TSThread *)thread
                                     messageSender:(OWSMessageSender *)messageSender
                                        completion:(void (^_Nullable)(NSError *_Nullable error))completion;

// This method will create and/or remove any offers and indicators
// necessary for this thread.  This includes:
//
// * Block offers.
// * "Add to contacts" offers.
// * Unread indicators.
//
// Parameters:
//
// * hideUnreadMessagesIndicator: If YES, the "unread indicator" has
//   been cleared and should not be shown.
// * firstUnseenInteractionTimestamp: A snapshot of unseen message state
//   when we entered the conversation view.  See comments on
//   ThreadOffersAndIndicators.
// * maxRangeSize: Loading a lot of messages in conversation view is
//   slow and unwieldy.  This number represents the maximum current
//   size of the "load window" in that view. The unread indicator should
//   always be inserted within that window.
+ (ThreadDynamicInteractions *)ensureDynamicInteractionsForThread:(TSThread *)thread
                                                  contactsManager:(OWSContactsManager *)contactsManager
                                                  blockingManager:(OWSBlockingManager *)blockingManager
                                                     dbConnection:(YapDatabaseConnection *)dbConnection
                                      hideUnreadMessagesIndicator:(BOOL)hideUnreadMessagesIndicator
                                  firstUnseenInteractionTimestamp:(nullable NSNumber *)firstUnseenInteractionTimestamp
                                                     maxRangeSize:(int)maxRangeSize;

+ (BOOL)shouldShowGroupProfileBannerInThread:(TSThread *)thread blockingManager:(OWSBlockingManager *)blockingManager;

// This method should be called right _before_ we send a message to a thread,
// since we want to auto-add contact threads to the profile whitelist if the
// conversation was initiated by the local user.
//
// Returns YES IFF the thread was just added to the profile whitelist.
+ (BOOL)addThreadToProfileWhitelistIfEmptyContactThread:(TSThread *)thread;

#pragma mark - Delete Content

+ (void)deleteAllContent;

#pragma mark - Find Content

+ (nullable TSInteraction *)findInteractionInThreadByTimestamp:(uint64_t)timestamp
                                                      authorId:(NSString *)authorId
                                                threadUniqueId:(NSString *)threadUniqueId
                                                   transaction:(YapDatabaseReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
