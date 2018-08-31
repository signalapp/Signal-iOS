//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Environment.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/SSKEnvironment.h>

static Environment *sharedEnvironment = nil;

@implementation Environment

+ (Environment *)shared
{
    OWSAssert(sharedEnvironment);

    return sharedEnvironment;
}

+ (void)setShared:(Environment *)environment
{
    // The main app environment should only be set once.
    //
    // App extensions may be opened multiple times in the same process,
    // so statics will persist.
    OWSAssert(!sharedEnvironment || !CurrentAppContext().isMainApp);
    OWSAssert(environment);

    sharedEnvironment = environment;
}

+ (void)clearSharedForTests
{
    sharedEnvironment = nil;
}

- (instancetype)initWithPreferences:(OWSPreferences *)preferences
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssert(preferences);

    _preferences = preferences;

    OWSSingletonAssert();

    return self;
}

- (OWSContactsManager *)contactsManager
{
    OWSAssert(SSKEnvironment.shared.contactsManager);

    return (OWSContactsManager *)SSKEnvironment.shared.contactsManager;
}

@end
