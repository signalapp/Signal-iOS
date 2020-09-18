//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "AppReadiness.h"
#import <SignalCoreKit/Threading.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppReadiness ()

@property (nonatomic, readonly) ReadyFlag *readyFlag;

@end

#pragma mark -

@implementation AppReadiness

+ (instancetype)shared
{
    static AppReadiness *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    _readyFlag = [[ReadyFlag alloc] initWithName:@"AppReadiness" queueMode:QueueModeMainThreadOnly];

    return self;
}

+ (BOOL)isAppReady
{
    AppReadiness *instance = self.shared;
    return [instance.readyFlag isSet];
}

+ (void)runNowOrWhenAppWillBecomeReady:(AppReadyBlock)block
{
    DispatchMainThreadSafe(^{ [self.shared runNowOrWhenAppWillBecomeReady:block]; });
}

- (void)runNowOrWhenAppWillBecomeReady:(AppReadyBlock)block
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(block);

    if (CurrentAppContext().isRunningTests) {
        // We don't need to do any "on app ready" work in the tests.
        return;
    }

    [self.readyFlag runNowOrWhenWillBecomeReady:block];
}

+ (void)runNowOrWhenAppDidBecomeReady:(AppReadyBlock)block
{
    DispatchMainThreadSafe(^{ [self.shared runNowOrWhenAppDidBecomeReady:block]; });
}

- (void)runNowOrWhenAppDidBecomeReady:(AppReadyBlock)block
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(block);

    if (CurrentAppContext().isRunningTests) {
        // We don't need to do any "on app ready" work in the tests.
        return;
    }

    [self.readyFlag runNowOrWhenDidBecomeReady:block];
}

+ (void)runNowOrWhenAppDidBecomeReadyPolite:(AppReadyBlock)block
{
    DispatchMainThreadSafe(^{ [self.shared runNowOrWhenAppDidBecomeReadyPolite:block]; });
}

// We now have many (36+ in best case; many more in worst case)
// "app did become ready" blocks, many of which
// perform database writes. This can cause a "stampede" of writes
// as the app becomes ready. This can lead to 0x8badf00d crashes
// as the main thread can block behind these writes while trying
// to perform a checkpoint. The risk is highest on old devices
// with large databases. It can also simply cause the main thread
// to be less responsive.
//
// Most "App did become ready" blocks should be performed _soon_
// after launch but don't need to be performed sync. Therefore
// any blocks we
// perform them one-by-one with slight delays between them to
// reduce the risk of starving the main thread, especially if
// any given block is expensive.
- (void)runNowOrWhenAppDidBecomeReadyPolite:(AppReadyBlock)block
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(block);

    if (CurrentAppContext().isRunningTests) {
        // We don't need to do any "on app ready" work in the tests.
        return;
    }

    [self.readyFlag runNowOrWhenDidBecomeReadyPolite:block];
}

+ (void)setAppIsReady
{
    [self.shared setAppIsReady];
}

- (void)setAppIsReady
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(!self.readyFlag.isSet);

    OWSLogInfo(@"");

    [self.readyFlag setIsReady];
}

@end

NS_ASSUME_NONNULL_END
