//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "Environment.h"
#import "OWSPreferences.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/SSKEnvironment.h>

NS_ASSUME_NONNULL_BEGIN

static Environment *sharedEnvironment = nil;

@interface Environment ()

@property (nonatomic) OWSPreferences *preferencesRef;
@property (nonatomic) id<OWSProximityMonitoringManager> proximityMonitoringManagerRef;
@property (nonatomic) OWSSounds *soundsRef;
@property (nonatomic) LaunchJobs *launchJobsRef;
@property (nonatomic) BroadcastMediaMessageJobQueue *broadcastMediaMessageJobQueueRef;
@property (nonatomic) OWSOrphanDataCleaner *orphanDataCleanerRef;
@property (nonatomic) AvatarBuilder *avatarBuilderRef;

@end

#pragma mark -

@implementation Environment

+ (Environment *)shared
{
    OWSAssertDebug(sharedEnvironment);

    return sharedEnvironment;
}

+ (void)setShared:(Environment *)environment
{
    // The main app environment should only be set once.
    //
    // App extensions may be opened multiple times in the same process,
    // so statics will persist.
    OWSAssertDebug(environment);
    OWSAssertDebug(!sharedEnvironment || !CurrentAppContext().isMainApp || CurrentAppContext().isRunningTests);

    sharedEnvironment = environment;
}

- (instancetype)initWithIncomingContactSyncJobQueue:(OWSIncomingContactSyncJobQueue *)incomingContactSyncJobQueue
                          incomingGroupSyncJobQueue:(OWSIncomingGroupSyncJobQueue *)incomingGroupSyncJobQueue
                                         launchJobs:(LaunchJobs *)launchJobs
                                        preferences:(OWSPreferences *)preferences
                         proximityMonitoringManager:(id<OWSProximityMonitoringManager>)proximityMonitoringManager
                                             sounds:(OWSSounds *)sounds
                      broadcastMediaMessageJobQueue:(BroadcastMediaMessageJobQueue *)broadcastMediaMessageJobQueue
                                  orphanDataCleaner:(OWSOrphanDataCleaner *)orphanDataCleaner
                                      avatarBuilder:(AvatarBuilder *)avatarBuilder
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(incomingGroupSyncJobQueue);
    OWSAssertDebug(incomingContactSyncJobQueue);
    OWSAssertDebug(launchJobs);
    OWSAssertDebug(preferences);
    OWSAssertDebug(proximityMonitoringManager);
    OWSAssertDebug(sounds);
    OWSAssertDebug(broadcastMediaMessageJobQueue);
    OWSAssertDebug(orphanDataCleaner);
    OWSAssertDebug(avatarBuilder);

    _incomingContactSyncJobQueueRef = incomingContactSyncJobQueue;
    _incomingGroupSyncJobQueueRef = incomingGroupSyncJobQueue;
    _launchJobsRef = launchJobs;
    _preferencesRef = preferences;
    _proximityMonitoringManagerRef = proximityMonitoringManager;
    _soundsRef = sounds;
    _broadcastMediaMessageJobQueueRef = broadcastMediaMessageJobQueue;
    _orphanDataCleanerRef = orphanDataCleaner;
    _avatarBuilderRef = avatarBuilder;

    OWSSingletonAssert();

    return self;
}

@end

NS_ASSUME_NONNULL_END
