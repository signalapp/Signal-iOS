//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/SSKEnvironment.h>

@class BroadcastMediaMessageJobQueue;
@class ContactsViewHelper;
@class LaunchJobs;
@class OWSAudioSession;
@class OWSContactsManager;
@class OWSIncomingContactSyncJobQueue;
@class OWSIncomingGroupSyncJobQueue;
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
       broadcastMediaMessageJobQueue:(BroadcastMediaMessageJobQueue *)broadcastMediaMessageJobQueue;

@property (nonatomic, readonly) OWSAudioSession *audioSession;
@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSIncomingContactSyncJobQueue *incomingContactSyncJobQueue;
@property (nonatomic, readonly) OWSIncomingGroupSyncJobQueue *incomingGroupSyncJobQueue;
@property (nonatomic, readonly) LaunchJobs *launchJobs;
@property (nonatomic, readonly) id<OWSProximityMonitoringManager> proximityMonitoringManager;
@property (nonatomic, readonly) OWSPreferences *preferences;
@property (nonatomic, readonly) OWSSounds *sounds;
@property (nonatomic, readonly) OWSWindowManager *windowManager;
@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;
@property (nonatomic, readonly) BroadcastMediaMessageJobQueue *broadcastMediaMessageJobQueue;

@property (class, nonatomic) Environment *shared;

#ifdef DEBUG
// Should only be called by tests.
+ (void)clearSharedForTests;
#endif

@end
