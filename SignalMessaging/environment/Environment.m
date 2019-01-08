//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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
                         preferences:(OWSPreferences *)preferences
          proximityMonitoringManager:(id<OWSProximityMonitoringManager>)proximityMonitoringManager
                              sounds:(OWSSounds *)sounds
                       windowManager:(OWSWindowManager *)windowManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(audioSession);
    OWSAssertDebug(preferences);
    OWSAssertDebug(proximityMonitoringManager);
    OWSAssertDebug(sounds);
    OWSAssertDebug(windowManager);

    _audioSession = audioSession;
    _preferences = preferences;
    _proximityMonitoringManager = proximityMonitoringManager;
    _sounds = sounds;
    _windowManager = windowManager;

    OWSSingletonAssert();

    return self;
}

- (OWSContactsManager *)contactsManager
{
    return (OWSContactsManager *)SSKEnvironment.shared.contactsManager;
}

@end
