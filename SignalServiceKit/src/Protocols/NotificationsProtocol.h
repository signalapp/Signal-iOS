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
                            inThread:(TSThread *)thread
                         transaction:(SDSAnyReadTransaction *)transaction;

- (void)notifyUserForReaction:(OWSReaction *)reaction
            onOutgoingMessage:(TSOutgoingMessage *)message
                     inThread:(TSThread *)thread
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

- (void)notifyUserForGRDBMigration;

@end

NS_ASSUME_NONNULL_END
