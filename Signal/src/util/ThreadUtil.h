//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSBlockingManager;
@class OWSContactsManager;
@class OWSMessageSender;
@class SignalAttachment;
@class TSContactThread;
@class TSInteraction;
@class YapDatabaseConnection;
@class TSThread;
@class TSUnreadIndicatorInteraction;

@interface ThreadDynamicInteractions : NSObject

// If there are unseen messages in the thread, this is the index
// of the unseen indicator, counting from the _end_ of the conversation
// history.
//
// This is used by MessageViewController to increase the
// range size of the mappings (the load window of the conversation)
// to include the unread indicator.
@property (nonatomic, nullable) NSNumber *unreadIndicatorPosition;

// If there are unseen messages in the thread, this is the timestamp
// of the oldest unseen messaage.
//
// Once we enter messages view, we mark all messages read, so we need
// a snapshot of what the first unread message was when we entered the
// view so that we can call ensureDynamicInteractionsForThread:...
// repeatedly. The unread indicator should continue to show up until
// it has been cleared, at which point hideUnreadMessagesIndicator is
// YES in ensureDynamicInteractionsForThread:...
@property (nonatomic, nullable) NSNumber *firstUnseenInteractionTimestamp;

- (void)clearUnreadIndicatorState;

@end

#pragma mark -

@class TSOutgoingMessage;

@interface ThreadUtil : NSObject

+ (TSOutgoingMessage *)sendMessageWithText:(NSString *)text
                                  inThread:(TSThread *)thread
                             messageSender:(OWSMessageSender *)messageSender;

+ (TSOutgoingMessage *)sendMessageWithAttachment:(SignalAttachment *)attachment
                                        inThread:(TSThread *)thread
                                   messageSender:(OWSMessageSender *)messageSender;

+ (TSOutgoingMessage *)sendMessageWithAttachment:(SignalAttachment *)attachment
                                        inThread:(TSThread *)thread
                                   messageSender:(OWSMessageSender *)messageSender
                                    ignoreErrors:(BOOL)ignoreErrors;

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

@end

NS_ASSUME_NONNULL_END
