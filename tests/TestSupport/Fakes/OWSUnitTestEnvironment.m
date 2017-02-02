//  Created by Michael Kirk on 12/18/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSUnitTestEnvironment.h"
#import "OWSFakeCallMessageHandler.h"
#import "OWSFakeContactsManager.h"
#import "OWSFakeNotificationsManager.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSUnitTestEnvironment

- (instancetype)init
{
    return [super initWithCallMessageHandler:[OWSFakeCallMessageHandler new]
                             contactsManager:[OWSFakeContactsManager new]
                        notificationsManager:[OWSFakeNotificationsManager new]];
}

@end

NS_ASSUME_NONNULL_END
