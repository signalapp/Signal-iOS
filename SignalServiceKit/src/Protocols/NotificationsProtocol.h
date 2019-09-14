//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class TSErrorMessage;
@class TSIncomingMessage;
@class TSInfoMessage;
@class TSThread;
@class ThreadlessErrorMessage;

@protocol ContactsManagerProtocol;

@protocol NotificationsProtocol <NSObject>

- (void)notifyUserForIncomingMessage:(TSIncomingMessage *)incomingMessage
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

@end

NS_ASSUME_NONNULL_END
