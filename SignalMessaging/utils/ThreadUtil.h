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

+ (TSOutgoingMessage *)sendMessageWithContactShare:(OWSContact *)contactShare
                                          inThread:(TSThread *)thread
                                     messageSender:(OWSMessageSender *)messageSender
                                        completion:(void (^_Nullable)(NSError *_Nullable error))completion;

+ (void)sendLeaveGroupMessageInThread:(TSGroupThread *)thread
             presentingViewController:(UIViewController *)presentingViewController
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
