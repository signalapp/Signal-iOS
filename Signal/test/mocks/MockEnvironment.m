//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "MockEnvironment.h"
#import <SignalMessaging/OWSPreferences.h>

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
    OWSPreferences *preferences = [OWSPreferences new];
    self = [super initWithPreferences:preferences];
    OWSAssertDebug(self);
    return self;
}

@end

NS_ASSUME_NONNULL_END
