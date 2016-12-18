//  Created by Michael Kirk on 12/18/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSFakeNotificationsManager.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSFakeNotificationsManager

- (void)notifyUserForIncomingMessage:(TSIncomingMessage *)incomingMessage
                                from:(NSString *)name
                            inThread:(TSThread *)thread
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (void)notifyUserForErrorMessage:(TSErrorMessage *)error inThread:(TSThread *)thread
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}


@end

NS_ASSUME_NONNULL_END
