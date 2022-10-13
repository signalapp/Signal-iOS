//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/SSKEnvironment.h>

NS_ASSUME_NONNULL_BEGIN

@class AvatarBuilder;
@class BroadcastMediaMessageJobQueue;
@class LaunchJobs;
@class LightweightCallManager;
@class OWSIncomingContactSyncJobQueue;
@class OWSIncomingGroupSyncJobQueue;
@class OWSOrphanDataCleaner;
@class OWSPreferences;
@class OWSSounds;

@protocol OWSProximityMonitoringManager;

/**
 *
 * Environment is a data and data accessor class.
 * It handles application-level component wiring in order to support mocks for testing.
 * It also handles network configuration for testing/deployment server configurations.
 *
 **/
// TODO: Rename to SMGEnvironment?
@interface Environment : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithIncomingContactSyncJobQueue:(OWSIncomingContactSyncJobQueue *)incomingContactSyncJobQueue
                          incomingGroupSyncJobQueue:(OWSIncomingGroupSyncJobQueue *)incomingGroupSyncJobQueue
                                         launchJobs:(LaunchJobs *)launchJobs
                                        preferences:(OWSPreferences *)preferences
                         proximityMonitoringManager:(id<OWSProximityMonitoringManager>)proximityMonitoringManager
                                             sounds:(OWSSounds *)sounds
                      broadcastMediaMessageJobQueue:(BroadcastMediaMessageJobQueue *)broadcastMediaMessageJobQueue
                                  orphanDataCleaner:(OWSOrphanDataCleaner *)orphanDataCleaner
                                      avatarBuilder:(AvatarBuilder *)avatarBuilder;

@property (nonatomic, readonly) OWSIncomingContactSyncJobQueue *incomingContactSyncJobQueueRef;
@property (nonatomic, readonly) OWSIncomingGroupSyncJobQueue *incomingGroupSyncJobQueueRef;
@property (nonatomic, readonly) LaunchJobs *launchJobsRef;
@property (nonatomic, readonly) id<OWSProximityMonitoringManager> proximityMonitoringManagerRef;
@property (nonatomic, readonly) OWSPreferences *preferencesRef;
@property (nonatomic, readonly) OWSSounds *soundsRef;
@property (nonatomic, readonly) BroadcastMediaMessageJobQueue *broadcastMediaMessageJobQueueRef;
@property (nonatomic, readonly) OWSOrphanDataCleaner *orphanDataCleanerRef;
@property (nonatomic, readonly) AvatarBuilder *avatarBuilderRef;

// This property is configured after Environment is created.
@property (atomic, nullable) LightweightCallManager *lightweightCallManagerRef;

@property (class, nonatomic) Environment *shared;

@end

NS_ASSUME_NONNULL_END
