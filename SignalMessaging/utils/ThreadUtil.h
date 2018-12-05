//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSBlockingManager;
@class OWSContactsManager;
@class OWSMessageSender;
@class OWSUnreadIndicator;
@class SignalAttachment;
@class TSContactThread;
@class TSGroupThread;
@class TSInteraction;
@class TSThread;
@class YapDatabaseConnection;
@class YapDatabaseReadTransaction;

@interface ThreadDynamicInteractions : NSObject

// Represents the "reverse index" of the focus message, if any.
// The "reverse index" is the distance of this interaction from
// the last interaction in the thread.  Therefore the last interaction
// will have a "reverse index" of zero.
//
// We use "reverse indices" because (among other uses) we use this to
// determine the initial load window size.
@property (nonatomic, nullable, readonly) NSNumber *focusMessagePosition;

@property (nonatomic, nullable, readonly) OWSUnreadIndicator *unreadIndicator;

- (void)clearUnreadIndicatorState;

@end

#pragma mark -

@class OWSContact;
@class OWSQuotedReplyModel;
@class TSOutgoingMessage;
@class YapDatabaseReadWriteTransaction;

@interface ThreadUtil : NSObject

#pragma mark - Durable Message Enqueue

+ (TSOutgoingMessage *)enqueueMessageWithText:(NSString *)text
                                     inThread:(TSThread *)thread
                             quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                  transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (TSOutgoingMessage *)enqueueMessageWithAttachment:(SignalAttachment *)attachment
                                           inThread:(TSThread *)thread
                                   quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel;

+ (TSOutgoingMessage *)enqueueMessageWithAttachments:(NSArray<SignalAttachment *> *)attachments
                                         messageBody:(nullable NSString *)messageBody
                                            inThread:(TSThread *)thread
                                    quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel;

+ (TSOutgoingMessage *)enqueueMessageWithContactShare:(OWSContact *)contactShare inThread:(TSThread *)thread;
+ (void)enqueueLeaveGroupMessageInThread:(TSGroupThread *)thread;

#pragma mark - Non-Durable Sending

// Used by SAE and "reply from lockscreen", otherwise we should use the durable `enqueue` counterpart
+ (TSOutgoingMessage *)sendMessageNonDurablyWithText:(NSString *)text
                                            inThread:(TSThread *)thread
                                    quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                       messageSender:(OWSMessageSender *)messageSender
                                             success:(void (^)(void))successHandler
                                             failure:(void (^)(NSError *error))failureHandler;

// Used by SAE, otherwise we should use the durable `enqueue` counterpart
+ (TSOutgoingMessage *)sendMessageNonDurablyWithAttachments:(NSArray<SignalAttachment *> *)attachments
                                                   inThread:(TSThread *)thread
                                                messageBody:(nullable NSString *)messageBody
                                           quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                              messageSender:(OWSMessageSender *)messageSender
                                                 completion:(void (^_Nullable)(NSError *_Nullable error))completion;

// Used by SAE, otherwise we should use the durable `enqueue` counterpart
+ (TSOutgoingMessage *)sendMessageNonDurablyWithContactShare:(OWSContact *)contactShare
                                                    inThread:(TSThread *)thread
                                               messageSender:(OWSMessageSender *)messageSender
                                                  completion:(void (^_Nullable)(NSError *_Nullable error))completion;


#pragma mark - dynamic interactions

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
                                              lastUnreadIndicator:(nullable OWSUnreadIndicator *)lastUnreadIndicator
                                                   focusMessageId:(nullable NSString *)focusMessageId
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
