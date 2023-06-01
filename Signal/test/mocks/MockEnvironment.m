//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "MockEnvironment.h"
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalUI/ContactsViewHelper.h>
#import <SignalUI/SignalUI-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation MockEnvironment

+ (MockEnvironment *)activate
{
    MockEnvironment *instance = [[MockEnvironment alloc] init];
    [self setShared:instance];
    return instance;
}

- (instancetype)init
{
    // TODO: We should probably mock this out.
    OWSPreferences *preferences = [OWSPreferences new];
    id<OWSProximityMonitoringManager> proximityMonitoringManager = [OWSProximityMonitoringManagerImpl new];
    AvatarBuilder *avatarBuilder = [AvatarBuilder new];
    SignalMessagingJobQueues *smJobQueues = [SignalMessagingJobQueues new];

    self = [super initWithPreferences:preferences
           proximityMonitoringManager:proximityMonitoringManager
                        avatarBuilder:avatarBuilder
                          smJobQueues:smJobQueues];

    OWSAssertDebug(self);
    return self;
}

@end

NS_ASSUME_NONNULL_END
