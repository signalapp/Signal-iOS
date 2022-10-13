//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "MockEnvironment.h"
#import "OWSWindowManager.h"
#import <SignalMessaging/OWSOrphanDataCleaner.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/OWSSounds.h>
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
    OWSIncomingContactSyncJobQueue *incomingContactSyncJobQueue = [OWSIncomingContactSyncJobQueue new];
    OWSIncomingGroupSyncJobQueue *incomingGroupSyncJobQueue = [OWSIncomingGroupSyncJobQueue new];
    LaunchJobs *launchJobs = [LaunchJobs new];
    OWSPreferences *preferences = [OWSPreferences new];
    OWSSounds *sounds = [OWSSounds new];
    id<OWSProximityMonitoringManager> proximityMonitoringManager = [OWSProximityMonitoringManagerImpl new];
    BroadcastMediaMessageJobQueue *broadcastMediaMessageJobQueue = [BroadcastMediaMessageJobQueue new];
    OWSOrphanDataCleaner *orphanDataCleaner = [OWSOrphanDataCleaner new];
    AvatarBuilder *avatarBuilder = [AvatarBuilder new];

    self = [super initWithIncomingContactSyncJobQueue:incomingContactSyncJobQueue
                            incomingGroupSyncJobQueue:incomingGroupSyncJobQueue
                                           launchJobs:launchJobs
                                          preferences:preferences
                           proximityMonitoringManager:proximityMonitoringManager
                                               sounds:sounds
                        broadcastMediaMessageJobQueue:broadcastMediaMessageJobQueue
                                    orphanDataCleaner:orphanDataCleaner
                                        avatarBuilder:avatarBuilder];

    OWSAssertDebug(self);
    return self;
}

@end

NS_ASSUME_NONNULL_END
