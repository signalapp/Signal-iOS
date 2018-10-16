//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Environment.h"
#import "OWSPreferences.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/SSKEnvironment.h>

static Environment *sharedEnvironment = nil;

@interface Environment ()

@property (nonatomic) OWSContactsManager *contactsManager;
@property (nonatomic) OWSPreferences *preferences;
@property (nonatomic) OWSSyncManager *syncManager;
@property (nonatomic) OWSSounds *sounds;
@property (nonatomic) LockInteractionController *lockInteractionController;
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

- (instancetype)initWithPreferences:(OWSPreferences *)preferences
                        syncManager:(OWSSyncManager *)syncManager
                             sounds:(OWSSounds *)sounds
          lockInteractionController:(LockInteractionController *)lockInteractionController
                      windowManager:(OWSWindowManager *)windowManager {
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(preferences);
    OWSAssertDebug(syncManager);
    OWSAssertDebug(sounds);
    OWSAssertDebug(lockInteractionController);
    OWSAssertDebug(windowManager);

    _preferences = preferences;
    _syncManager = syncManager;
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
