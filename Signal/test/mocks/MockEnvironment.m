//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "MockEnvironment.h"
#import "OWSBackup.h"
#import "OWSSyncManager.h"
#import "OWSWindowManager.h"
#import <SignalMessaging/LockInteractionController.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/OWSSounds.h>

NS_ASSUME_NONNULL_BEGIN

@implementation MockEnvironment

+ (MockEnvironment *)activate
{
    MockEnvironment *instance = [MockEnvironment new];
    [self setShared:instance];
    return instance;
}

- (instancetype)init
{
    OWSPrimaryStorage *primaryStorage = SSKEnvironment.shared.primaryStorage;
    OWSAssertDebug(primaryStorage);

    // TODO: We should probably mock this out.
    OWSPreferences *preferences = [OWSPreferences new];
    OWSSyncManager *syncManager = [[OWSSyncManager alloc] initDefault];
    OWSSounds *sounds = [[OWSSounds alloc] initWithPrimaryStorage:primaryStorage];
    LockInteractionController *lockInteractionController = [[LockInteractionController alloc] initDefault];
    OWSWindowManager *windowManager = [[OWSWindowManager alloc] initDefault];

    self = [super initWithPreferences:preferences
                          syncManager:syncManager
                               sounds:sounds
            lockInteractionController:lockInteractionController
                        windowManager:windowManager];
    OWSAssertDebug(self);
    return self;
}

@end

NS_ASSUME_NONNULL_END
