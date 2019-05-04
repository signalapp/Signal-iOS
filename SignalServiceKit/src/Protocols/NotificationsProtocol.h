//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class TSErrorMessage;
@class TSIncomingMessage;
@class TSThread;

@protocol ContactsManagerProtocol;

@protocol NotificationsProtocol <NSObject>

- (void)notifyUserForIncomingMessage:(TSIncomingMessage *)incomingMessage
                            inThread:(TSThread *)thread
                         transaction:(SDSAnyReadTransaction *)transaction;

- (void)notifyUserForErrorMessage:(TSErrorMessage *)error
                           thread:(TSThread *)thread
                      transaction:(SDSAnyWriteTransaction *)transaction;

- (void)notifyUserForThreadlessErrorMessage:(TSErrorMessage *)error
                                transaction:(SDSAnyWriteTransaction *)transaction;

- (void)clearAllNotifications;

@end

NS_ASSUME_NONNULL_END
