//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
@property (nonatomic) OWSOrphanDataCleaner *orphanDataCleanerRef;
@property (nonatomic) AvatarBuilder *avatarBuilderRef;
@property (nonatomic) SignalMessagingJobQueues *signalMessagingJobQueuesRef;

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

- (instancetype)initWithLaunchJobs:(LaunchJobs *)launchJobs
                       preferences:(OWSPreferences *)preferences
        proximityMonitoringManager:(id<OWSProximityMonitoringManager>)proximityMonitoringManager
                            sounds:(OWSSounds *)sounds
                 orphanDataCleaner:(OWSOrphanDataCleaner *)orphanDataCleaner
                     avatarBuilder:(AvatarBuilder *)avatarBuilder
                       smJobQueues:(SignalMessagingJobQueues *)smJobQueues
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(launchJobs);
    OWSAssertDebug(preferences);
    OWSAssertDebug(proximityMonitoringManager);
    OWSAssertDebug(sounds);
    OWSAssertDebug(orphanDataCleaner);
    OWSAssertDebug(avatarBuilder);
    OWSAssertDebug(smJobQueues);

    _launchJobsRef = launchJobs;
    _preferencesRef = preferences;
    _proximityMonitoringManagerRef = proximityMonitoringManager;
    _soundsRef = sounds;
    _orphanDataCleanerRef = orphanDataCleaner;
    _avatarBuilderRef = avatarBuilder;
    _signalMessagingJobQueuesRef = smJobQueues;

    OWSSingletonAssert();

    return self;
}

@end

NS_ASSUME_NONNULL_END
