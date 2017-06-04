//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSUnitTestEnvironment.h"
#import "OWSFakeCallMessageHandler.h"
#import "OWSFakeContactsManager.h"
#import "OWSFakeMessageSender.h"
#import "OWSFakeNotificationsManager.h"
#import "OWSFakePreferences.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSUnitTestEnvironment

+ (void)ensureSetup
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self setSharedEnv:[[self alloc] initDefault]];
    });
}

- (instancetype)initDefault
{
    return [super initWithCallMessageHandler:[OWSFakeCallMessageHandler new]
                             contactsManager:[OWSFakeContactsManager new]
                               messageSender:[OWSFakeMessageSender new]
                        notificationsManager:[OWSFakeNotificationsManager new]
                                 preferences:[OWSFakePreferences new]];    
}

@end

NS_ASSUME_NONNULL_END
