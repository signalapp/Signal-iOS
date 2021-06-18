//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/SSKEnvironment.h>

@class AvatarBuilder;
@class BroadcastMediaMessageJobQueue;
@class ChatColors;
@class ContactsViewHelper;
@class LaunchJobs;
@class OWSAudioSession;
@class OWSIncomingContactSyncJobQueue;
@class OWSIncomingGroupSyncJobQueue;
@class OWSOrphanDataCleaner;
@class OWSPreferences;
@class OWSSounds;
@class OWSWindowManager;

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

- (instancetype)initWithAudioSession:(OWSAudioSession *)audioSession
         incomingContactSyncJobQueue:(OWSIncomingContactSyncJobQueue *)incomingContactSyncJobQueue
           incomingGroupSyncJobQueue:(OWSIncomingGroupSyncJobQueue *)incomingGroupSyncJobQueue
                          launchJobs:(LaunchJobs *)launchJobs
                         preferences:(OWSPreferences *)preferences
          proximityMonitoringManager:(id<OWSProximityMonitoringManager>)proximityMonitoringManager
                              sounds:(OWSSounds *)sounds
                       windowManager:(OWSWindowManager *)windowManager
                  contactsViewHelper:(ContactsViewHelper *)contactsViewHelper
       broadcastMediaMessageJobQueue:(BroadcastMediaMessageJobQueue *)broadcastMediaMessageJobQueue
                   orphanDataCleaner:(OWSOrphanDataCleaner *)orphanDataCleaner
                          chatColors:(ChatColors *)chatColors
                       avatarBuilder:(AvatarBuilder *)avatarBuilder;

@property (nonatomic, readonly) OWSAudioSession *audioSessionRef;
@property (nonatomic, readonly) OWSIncomingContactSyncJobQueue *incomingContactSyncJobQueueRef;
@property (nonatomic, readonly) OWSIncomingGroupSyncJobQueue *incomingGroupSyncJobQueueRef;
@property (nonatomic, readonly) LaunchJobs *launchJobsRef;
@property (nonatomic, readonly) id<OWSProximityMonitoringManager> proximityMonitoringManagerRef;
@property (nonatomic, readonly) OWSPreferences *preferencesRef;
@property (nonatomic, readonly) OWSSounds *soundsRef;
@property (nonatomic, readonly) OWSWindowManager *windowManagerRef;
@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelperRef;
@property (nonatomic, readonly) BroadcastMediaMessageJobQueue *broadcastMediaMessageJobQueueRef;
@property (nonatomic, readonly) OWSOrphanDataCleaner *orphanDataCleanerRef;
@property (nonatomic, readonly) ChatColors *chatColorsRef;
@property (nonatomic, readonly) AvatarBuilder *avatarBuilderRef;

@property (class, nonatomic) Environment *shared;

#ifdef DEBUG
// Should only be called by tests.
+ (void)clearSharedForTests;
#endif

@end
