//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@class TSErrorMessage;
@class TSIncomingMessage;
@class TSThread;
@protocol ContactsManagerProtocol;

@protocol NotificationsProtocol <NSObject>

- (void)notifyUserForIncomingMessage:(TSIncomingMessage *)incomingMessage
                            inThread:(TSThread *)thread
                     contactsManager:(id<ContactsManagerProtocol>)contactsManager;

- (void)notifyUserForErrorMessage:(TSErrorMessage *)error inThread:(TSThread *)thread;

@end
