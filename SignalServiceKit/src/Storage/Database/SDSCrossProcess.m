//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "SDSCrossProcess.h"
#import <SignalCoreKit/OWSAsserts.h>
#import <SignalServiceKit/DarwinNotificationCenter.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

// NOTE: CFNotificationCenterGetDarwinNotifyCenter() might offer a better / equivalent solution,
//       but it wasn't working for me and so I moved on.

pid_t localPid(void)
{
    static dispatch_once_t onceToken;
    static pid_t pid;
    dispatch_once(&onceToken, ^{
        pid = getpid();
    });
    return pid;
}

#pragma mark -

@interface SDSCrossProcess ()

@property (nonatomic) int notifyToken;

@end

#pragma mark -

@implementation SDSCrossProcess

- (id)init
{
    if (self = [super init]) {
        self.notifyToken = DarwinNotificationInvalidObserver;

        [self start];
    }
    return self;
}

- (void)dealloc
{
    [self stop];
}

- (void)start
{
    [self stop];

    __weak SDSCrossProcess *weakSelf = self;
    self.notifyToken = [DarwinNotificationCenter addObserverForName:DarwinNotificationName.sdsCrossProcess
                                                              queue:dispatch_get_main_queue()
                                                         usingBlock:^(int token) {
                                                             [weakSelf handleNotification:token];
                                                         }];
}

- (void)handleNotification:(int)token
{
    OWSAssertIsOnMainThread();

    uint64_t fromPid = [DarwinNotificationCenter getStateForObserver:token];
    BOOL isLocal = fromPid == (uint64_t)localPid();
    if (isLocal) {
        return;
    }

    OWSLogVerbose(@"Cross process write from %llu", fromPid);
    if (self.callback) {
        self.callback();
    }
}

- (void)stop
{
    if ([DarwinNotificationCenter isValidObserver:self.notifyToken]) {
        [DarwinNotificationCenter removeObserver:self.notifyToken];
    }
    self.notifyToken = DarwinNotificationInvalidObserver;
}

- (void)notifyChangedAsync
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self notifyChanged];
    });
}

- (void)notifyChanged
{
    OWSAssertIsOnMainThread();

    if (![DarwinNotificationCenter isValidObserver:self.notifyToken]) {
        [self start];
    }

    [DarwinNotificationCenter setState:localPid() forObserver:self.notifyToken];
    [DarwinNotificationCenter postNotificationName:DarwinNotificationName.sdsCrossProcess];
}

@end

NS_ASSUME_NONNULL_END
