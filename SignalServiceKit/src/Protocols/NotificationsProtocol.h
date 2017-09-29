//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@class TSErrorMessage;
@class TSIncomingMessage;
@class TSThread;
@class YapDatabaseReadTransaction;
@protocol ContactsManagerProtocol;

@protocol NotificationsProtocol <NSObject>

- (void)notifyUserForIncomingMessage:(TSIncomingMessage *)incomingMessage
                            inThread:(TSThread *)thread
                     contactsManager:(id<ContactsManagerProtocol>)contactsManager
                         transaction:(YapDatabaseReadTransaction *)transaction;

- (void)notifyUserForErrorMessage:(TSErrorMessage *)error inThread:(TSThread *)thread;

@end
