//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeNotificationsManager.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

@implementation OWSFakeNotificationsManager

- (void)notifyUserForIncomingMessage:(TSIncomingMessage *)incomingMessage
                            inThread:(TSThread *)thread
                     contactsManager:(id<ContactsManagerProtocol>)contactsManager
                         transaction:(YapDatabaseReadTransaction *)transaction {
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (void)notifyUserForErrorMessage:(TSErrorMessage *)error
                           thread:(TSThread *)thread
                      transaction:(YapDatabaseReadWriteTransaction *)transaction {
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (void)notifyUserForThreadlessErrorMessage:(TSErrorMessage *)error
                                transaction:(YapDatabaseReadWriteTransaction *)transaction {
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (void)clearAllNotifications {
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

@end

#endif

NS_ASSUME_NONNULL_END
