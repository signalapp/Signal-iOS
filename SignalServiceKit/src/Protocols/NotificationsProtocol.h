//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
                         transaction:(SDSAnyReadTransaction *)transaction;

- (void)notifyUserForReaction:(OWSReaction *)reaction
            onOutgoingMessage:(TSOutgoingMessage *)message
                       thread:(TSThread *)thread
                  transaction:(SDSAnyReadTransaction *)transaction;

- (void)notifyUserForErrorMessage:(TSErrorMessage *)errorMessage
                           thread:(TSThread *)thread
                      transaction:(SDSAnyWriteTransaction *)transaction;

- (void)notifyUserForPreviewableInteraction:(TSInteraction<OWSPreviewText> *)previewableInteraction
                                     thread:(TSThread *)thread
                                 wantsSound:(BOOL)wantsSound
                                transaction:(SDSAnyWriteTransaction *)transaction NS_SWIFT_NAME(notifyUser(for:thread:wantsSound:transaction:));

- (void)notifyUserForThreadlessErrorMessage:(ThreadlessErrorMessage *)errorMessage
                                transaction:(SDSAnyWriteTransaction *)transaction;

- (void)clearAllNotifications;

- (void)cancelNotificationsForMessageId:(NSString *)uniqueMessageId NS_SWIFT_NAME(cancelNotifications(messageId:));
- (void)cancelNotificationsForReactionId:(NSString *)uniqueReactionId NS_SWIFT_NAME(cancelNotifications(reactionId:));

- (void)notifyUserForGRDBMigration;

@end

NS_ASSUME_NONNULL_END
