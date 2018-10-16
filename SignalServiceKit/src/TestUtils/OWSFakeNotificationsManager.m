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
    OWSLogInfo(@"");
}

- (void)notifyUserForErrorMessage:(TSErrorMessage *)error
                           thread:(TSThread *)thread
                      transaction:(YapDatabaseReadWriteTransaction *)transaction {
    OWSLogInfo(@"");
}

- (void)notifyUserForThreadlessErrorMessage:(TSErrorMessage *)error
                                transaction:(YapDatabaseReadWriteTransaction *)transaction {
    OWSLogInfo(@"");
}

- (void)clearAllNotifications {
    OWSLogInfo(@"");
}

@end

#endif

NS_ASSUME_NONNULL_END
