//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSErrorMessage;
@class TSIncomingMessage;
@class TSThread;
@class YapDatabaseReadTransaction;
@class YapDatabaseReadWriteTransaction;

@protocol ContactsManagerProtocol;

@protocol NotificationsProtocol <NSObject>

- (void)notifyUserForIncomingMessage:(TSIncomingMessage *)incomingMessage
                            inThread:(TSThread *)thread
                     contactsManager:(id<ContactsManagerProtocol>)contactsManager
                         transaction:(YapDatabaseReadTransaction *)transaction;

- (void)notifyUserForErrorMessage:(TSErrorMessage *)error
                           thread:(TSThread *)thread
                      transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (void)notifyUserForThreadlessErrorMessage:(TSErrorMessage *)error
                                transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (void)clearAllNotifications;

@end

NS_ASSUME_NONNULL_END
