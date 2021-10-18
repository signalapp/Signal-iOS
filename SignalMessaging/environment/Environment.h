//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/SSKEnvironment.h>

@class AvatarBuilder;
@class BroadcastMediaMessageJobQueue;
@class LaunchJobs;
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

@property (class, nonatomic) Environment *shared;

#ifdef TESTABLE_BUILD
// Should only be called by tests.
+ (void)clearSharedForTests;
#endif

@end
