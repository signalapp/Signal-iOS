//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "Environment.h"
#import "OWSPreferences.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/SSKEnvironment.h>

static Environment *sharedEnvironment = nil;

@interface Environment ()

@property (nonatomic) OWSAudioSession *audioSessionRef;
@property (nonatomic) OWSPreferences *preferencesRef;
@property (nonatomic) id<OWSProximityMonitoringManager> proximityMonitoringManagerRef;
@property (nonatomic) OWSSounds *soundsRef;
@property (nonatomic) OWSWindowManager *windowManagerRef;
@property (nonatomic) LaunchJobs *launchJobsRef;
@property (nonatomic) ContactsViewHelper *contactsViewHelperRef;
@property (nonatomic) BroadcastMediaMessageJobQueue *broadcastMediaMessageJobQueueRef;
@property (nonatomic) OWSOrphanDataCleaner *orphanDataCleanerRef;
@property (nonatomic) ChatColors *chatColorsRef;
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
    OWSAssertDebug(!sharedEnvironment || !CurrentAppContext().isMainApp);
    OWSAssertDebug(environment);

    sharedEnvironment = environment;
}

+ (void)clearSharedForTests
{
    sharedEnvironment = nil;
}

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
                       avatarBuilder:(AvatarBuilder *)avatarBuilder
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(audioSession);
    OWSAssertDebug(incomingGroupSyncJobQueue);
    OWSAssertDebug(incomingContactSyncJobQueue);
    OWSAssertDebug(launchJobs);
    OWSAssertDebug(preferences);
    OWSAssertDebug(proximityMonitoringManager);
    OWSAssertDebug(sounds);
    OWSAssertDebug(windowManager);
    OWSAssertDebug(contactsViewHelper);
    OWSAssertDebug(broadcastMediaMessageJobQueue);
    OWSAssertDebug(orphanDataCleaner);
    OWSAssertDebug(chatColors);
    OWSAssertDebug(avatarBuilder);

    _audioSessionRef = audioSession;
    _incomingContactSyncJobQueueRef = incomingContactSyncJobQueue;
    _incomingGroupSyncJobQueueRef = incomingGroupSyncJobQueue;
    _launchJobsRef = launchJobs;
    _preferencesRef = preferences;
    _proximityMonitoringManagerRef = proximityMonitoringManager;
    _soundsRef = sounds;
    _windowManagerRef = windowManager;
    _contactsViewHelperRef = contactsViewHelper;
    _broadcastMediaMessageJobQueueRef = broadcastMediaMessageJobQueue;
    _orphanDataCleanerRef = orphanDataCleaner;
    _chatColorsRef = chatColors;
    _avatarBuilderRef = avatarBuilder;

    OWSSingletonAssert();

    return self;
}

@end
