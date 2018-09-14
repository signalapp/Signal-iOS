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
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (void)notifyUserForErrorMessage:(TSErrorMessage *)error inThread:(TSThread *)thread
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}


@end

#endif

NS_ASSUME_NONNULL_END
