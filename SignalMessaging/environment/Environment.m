//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Environment.h"
#import "OWSPreferences.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/SSKEnvironment.h>

static Environment *sharedEnvironment = nil;

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

- (instancetype)initWithPreferences:(OWSPreferences *)preferences
                    contactsSyncing:(OWSContactsSyncing *)contactsSyncing
                             sounds:(OWSSounds *)sounds
          lockInteractionController:(LockInteractionController *)lockInteractionController
                      windowManager:(OWSWindowManager *)windowManager {
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(preferences);
    OWSAssertDebug(contactsSyncing);
    OWSAssertDebug(sounds);
    OWSAssertDebug(lockInteractionController);
    OWSAssertDebug(windowManager);

    _preferences = preferences;
    _contactsSyncing = contactsSyncing;
    _sounds = sounds;
    _lockInteractionController = lockInteractionController;
    _windowManager = windowManager;

    OWSSingletonAssert();

    return self;
}

- (OWSContactsManager *)contactsManager
{
    return (OWSContactsManager *)SSKEnvironment.shared.contactsManager;
}

@end
