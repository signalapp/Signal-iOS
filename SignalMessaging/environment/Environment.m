//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "Environment.h"
#import "OWSPreferences.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/SSKEnvironment.h>

static Environment *sharedEnvironment = nil;

@interface Environment ()

@property (nonatomic) OWSAudioSession *audioSession;
@property (nonatomic) OWSContactsManager *contactsManager;
@property (nonatomic) OWSPreferences *preferences;
@property (nonatomic) id<OWSProximityMonitoringManager> proximityMonitoringManager;
@property (nonatomic) OWSSounds *sounds;
@property (nonatomic) OWSWindowManager *windowManager;
@property (nonatomic) LaunchJobs *launchJobs;
@property (nonatomic) ContactsViewHelper *contactsViewHelper;
@property (nonatomic) BroadcastMediaMessageJobQueue *broadcastMediaMessageJobQueue;

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

    _audioSession = audioSession;
    _incomingContactSyncJobQueue = incomingContactSyncJobQueue;
    _incomingGroupSyncJobQueue = incomingGroupSyncJobQueue;
    _launchJobs = launchJobs;
    _preferences = preferences;
    _proximityMonitoringManager = proximityMonitoringManager;
    _sounds = sounds;
    _windowManager = windowManager;
    _contactsViewHelper = contactsViewHelper;
    _broadcastMediaMessageJobQueue = broadcastMediaMessageJobQueue;

    OWSSingletonAssert();

    return self;
}

- (OWSContactsManager *)contactsManager
{
    return (OWSContactsManager *)SSKEnvironment.shared.contactsManager;
}

@end
