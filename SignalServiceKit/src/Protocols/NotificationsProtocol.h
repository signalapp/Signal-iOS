//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSReaction;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class TSErrorMessage;
@class TSIncomingMessage;
@class TSInfoMessage;
@class TSOutgoingMessage;
@class TSThread;
@class ThreadlessErrorMessage;

@protocol ContactsManagerProtocol;

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

- (void)notifyUserForInfoMessage:(TSInfoMessage *)infoMessage
                          thread:(TSThread *)thread
                      wantsSound:(BOOL)wantsSound
                     transaction:(SDSAnyWriteTransaction *)transaction;

- (void)notifyUserForThreadlessErrorMessage:(ThreadlessErrorMessage *)errorMessage
                                transaction:(SDSAnyWriteTransaction *)transaction;

- (void)clearAllNotifications;

- (void)cancelNotificationsForMessageId:(NSString *)uniqueMessageId NS_SWIFT_NAME(cancelNotifications(messageId:));
- (void)cancelNotificationsForReactionId:(NSString *)uniqueReactionId NS_SWIFT_NAME(cancelNotifications(reactionId:));

- (void)notifyUserForGRDBMigration;

@end

NS_ASSUME_NONNULL_END
