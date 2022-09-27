//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSReaction;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class TSErrorMessage;
@class TSIncomingMessage;
@class TSInteraction;
@class TSOutgoingMessage;
@class TSThread;
@class ThreadlessErrorMessage;

@protocol ContactsManagerProtocol;
@protocol OWSPreviewText;

@protocol NotificationsProtocol <NSObject>

- (void)notifyUserForIncomingMessage:(TSIncomingMessage *)incomingMessage
                              thread:(TSThread *)thread
                         transaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(notifyUser(forIncomingMessage:thread:transaction:));

- (void)notifyUserForReaction:(OWSReaction *)reaction
            onOutgoingMessage:(TSOutgoingMessage *)message
                       thread:(TSThread *)thread
                  transaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(notifyUser(forReaction:onOutgoingMessage:thread:transaction:));

- (void)notifyUserForErrorMessage:(TSErrorMessage *)errorMessage
                           thread:(TSThread *)thread
                      transaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(notifyUser(forErrorMessage:thread:transaction:));

- (void)notifyUserForPreviewableInteraction:(TSInteraction<OWSPreviewText> *)previewableInteraction
                                     thread:(TSThread *)thread
                                 wantsSound:(BOOL)wantsSound
                                transaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(notifyUser(forPreviewableInteraction:thread:wantsSound:transaction:));

- (void)notifyUserForThreadlessErrorMessage:(ThreadlessErrorMessage *)errorMessage
                                transaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(notifyUser(forThreadlessErrorMessage:transaction:));

- (void)notifyTestPopulationOfErrorMessage:(NSString *)errorString;

- (void)clearAllNotifications;

- (void)cancelNotificationsForThreadId:(NSString *)uniqueMessageId NS_SWIFT_NAME(cancelNotifications(threadId:));
- (void)cancelNotificationsForMessageIds:(NSArray<NSString *> *)uniqueMessageIds
    NS_SWIFT_NAME(cancelNotifications(messageIds:));
- (void)cancelNotificationsForReactionId:(NSString *)uniqueReactionId NS_SWIFT_NAME(cancelNotifications(reactionId:));

@end

NS_ASSUME_NONNULL_END
