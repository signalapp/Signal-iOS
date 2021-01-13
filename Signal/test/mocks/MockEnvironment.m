//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "MockEnvironment.h"
#import "OWSBackup.h"
#import "OWSWindowManager.h"
#import <SignalMessaging/ContactsViewHelper.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/OWSSounds.h>
#import <SignalMessaging/SignalMessaging-Swift.h>

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
    OWSAudioSession *audioSession = [OWSAudioSession new];
    OWSIncomingContactSyncJobQueue *incomingContactSyncJobQueue = [OWSIncomingContactSyncJobQueue new];
    OWSIncomingGroupSyncJobQueue *incomingGroupSyncJobQueue = [OWSIncomingGroupSyncJobQueue new];
    LaunchJobs *launchJobs = [LaunchJobs new];
    OWSPreferences *preferences = [OWSPreferences new];
    OWSSounds *sounds = [OWSSounds new];
    id<OWSProximityMonitoringManager> proximityMonitoringManager = [OWSProximityMonitoringManagerImpl new];
    OWSWindowManager *windowManager = [[OWSWindowManager alloc] initDefault];
    ContactsViewHelper *contactsViewHelper = [ContactsViewHelper new];
    BroadcastMediaMessageJobQueue *broadcastMediaMessageJobQueue = [BroadcastMediaMessageJobQueue new];

    self = [super initWithAudioSession:audioSession
           incomingContactSyncJobQueue:incomingContactSyncJobQueue
             incomingGroupSyncJobQueue:incomingGroupSyncJobQueue
                            launchJobs:launchJobs
                           preferences:preferences
            proximityMonitoringManager:proximityMonitoringManager
                                sounds:sounds
                         windowManager:windowManager
                    contactsViewHelper:contactsViewHelper
         broadcastMediaMessageJobQueue:broadcastMediaMessageJobQueue];

    OWSAssertDebug(self);
    return self;
}

@end

NS_ASSUME_NONNULL_END
