//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "MockEnvironment.h"
#import "OWSBackup.h"
#import "OWSWindowManager.h"
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/OWSSounds.h>
#import <SignalMessaging/SignalMessaging-Swift.h>

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
    // TODO: We should probably mock this out.
    OWSAudioSession *audioSession = [OWSAudioSession new];
    OWSPreferences *preferences = [OWSPreferences new];
    OWSSounds *sounds = [OWSSounds new];
    id<OWSProximityMonitoringManager> proximityMonitoringManager = [OWSProximityMonitoringManagerImpl new];
    OWSWindowManager *windowManager = [[OWSWindowManager alloc] initDefault];

    self = [super initWithAudioSession:audioSession
                           preferences:preferences
            proximityMonitoringManager:proximityMonitoringManager
                                sounds:sounds
                         windowManager:windowManager];

    OWSAssertDebug(self);
    return self;
}

@end

NS_ASSUME_NONNULL_END
