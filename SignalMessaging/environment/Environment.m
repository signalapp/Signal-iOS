//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "Environment.h"
#import "OWSPreferences.h"
#import <SignalServiceKit/AppContext.h>

NS_ASSUME_NONNULL_BEGIN

static Environment *sharedEnvironment = nil;

@interface Environment ()

@property (nonatomic) OWSPreferences *preferencesRef;
@property (nonatomic) id<OWSProximityMonitoringManager> proximityMonitoringManagerRef;
@property (nonatomic) OWSSounds *soundsRef;
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

- (instancetype)initWithPreferences:(OWSPreferences *)preferences
         proximityMonitoringManager:(id<OWSProximityMonitoringManager>)proximityMonitoringManager
                      avatarBuilder:(AvatarBuilder *)avatarBuilder
                        smJobQueues:(SignalMessagingJobQueues *)smJobQueues
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(preferences);
    OWSAssertDebug(proximityMonitoringManager);
    OWSAssertDebug(avatarBuilder);
    OWSAssertDebug(smJobQueues);

    _preferencesRef = preferences;
    _proximityMonitoringManagerRef = proximityMonitoringManager;
    _avatarBuilderRef = avatarBuilder;
    _signalMessagingJobQueuesRef = smJobQueues;

    OWSSingletonAssert();

    return self;
}

@end

NS_ASSUME_NONNULL_END
