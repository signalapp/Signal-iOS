//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeNotificationsManager.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSFakeNotificationsManager

- (void)notifyUserForIncomingMessage:(TSIncomingMessage *)incomingMessage
                            inThread:(TSThread *)thread
                     contactsManager:(id<ContactsManagerProtocol>)contactsManager
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (void)notifyUserForErrorMessage:(TSErrorMessage *)error inThread:(TSThread *)thread
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}


@end

NS_ASSUME_NONNULL_END
