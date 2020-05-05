//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "AppReadiness.h"
#import <SignalCoreKit/Threading.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppReadiness ()

@property (atomic) BOOL isAppReady;

@property (nonatomic) NSMutableArray<AppReadyBlock> *appWillBecomeReadyBlocks;
@property (nonatomic) NSMutableArray<AppReadyBlock> *appDidBecomeReadyBlocks;
@property (nonatomic) NSMutableArray<AppReadyBlock> *appDidBecomeReadyPoliteBlocks;

@end

#pragma mark -

@implementation AppReadiness

+ (instancetype)sharedManager
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

    self.appWillBecomeReadyBlocks = [NSMutableArray new];
    self.appDidBecomeReadyBlocks = [NSMutableArray new];
    self.appDidBecomeReadyPoliteBlocks = [NSMutableArray new];

    return self;
}

+ (BOOL)isAppReady
{
    return [self.sharedManager isAppReady];
}

+ (void)runNowOrWhenAppWillBecomeReady:(AppReadyBlock)block
{
    DispatchMainThreadSafe(^{
        [self.sharedManager runNowOrWhenAppWillBecomeReady:block];
    });
}

- (void)runNowOrWhenAppWillBecomeReady:(AppReadyBlock)block
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(block);

    if (CurrentAppContext().isRunningTests) {
        // We don't need to do any "on app ready" work in the tests.
        return;
    }

    if (self.isAppReady) {
        block();
        return;
    }

    [self.appWillBecomeReadyBlocks addObject:block];
}

+ (void)runNowOrWhenAppDidBecomeReady:(AppReadyBlock)block
{
    DispatchMainThreadSafe(^{
        [self.sharedManager runNowOrWhenAppDidBecomeReady:block];
    });
}

- (void)runNowOrWhenAppDidBecomeReady:(AppReadyBlock)block
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(block);

    if (CurrentAppContext().isRunningTests) {
        // We don't need to do any "on app ready" work in the tests.
        return;
    }

    if (self.isAppReady) {
        block();
        return;
    }

    [self.appDidBecomeReadyBlocks addObject:block];
}

+ (void)runNowOrWhenAppDidBecomeReadyPolite:(AppReadyBlock)block
{
    DispatchMainThreadSafe(^{
        [self.sharedManager runNowOrWhenAppDidBecomeReadyPolite:block];
    });
}

- (void)runNowOrWhenAppDidBecomeReadyPolite:(AppReadyBlock)block
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(block);

    if (CurrentAppContext().isRunningTests) {
        // We don't need to do any "on app ready" work in the tests.
        return;
    }

    if (self.isAppReady) {
        block();
        return;
    }

    [self.appDidBecomeReadyPoliteBlocks addObject:block];
}

+ (void)setAppIsReady
{
    [self.sharedManager setAppIsReady];
}

- (void)setAppIsReady
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(!self.isAppReady);

    OWSLogInfo(@"");

    self.isAppReady = YES;

    [self runAppReadyBlocks];
}

- (void)runAppReadyBlocks
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.isAppReady);

    NSArray<AppReadyBlock> *appWillBecomeReadyBlocks = [self.appWillBecomeReadyBlocks copy];
    [self.appWillBecomeReadyBlocks removeAllObjects];
    NSArray<AppReadyBlock> *appDidBecomeReadyBlocks = [self.appDidBecomeReadyBlocks copy];
    [self.appDidBecomeReadyBlocks removeAllObjects];
    NSArray<AppReadyBlock> *appDidBecomeReadyPoliteBlocks = [self.appDidBecomeReadyPoliteBlocks copy];
    [self.appDidBecomeReadyPoliteBlocks removeAllObjects];

    // We invoke the _will become_ blocks before the _did become_ blocks.
    for (AppReadyBlock block in appWillBecomeReadyBlocks) {
        [BenchManager benchWithTitle:@"appWillBecomeReadyBlock" logIfLongerThan:0.01 logInProduction:YES block:block];
    }
    for (AppReadyBlock block in appDidBecomeReadyBlocks) {
        [BenchManager benchWithTitle:@"appDidBecomeReadyBlock" logIfLongerThan:0.01 logInProduction:YES block:block];
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
    [self runAppDidBecomeReadyPoliteBlocks:[appDidBecomeReadyPoliteBlocks mutableCopy]];
}

- (void)runAppDidBecomeReadyPoliteBlocks:(NSMutableArray<AppReadyBlock> *)blocks
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.isAppReady);

    if (blocks.count < 1) {
        return;
    }

    AppReadyBlock block = [blocks lastObject];
    [blocks removeLastObject];
    [BenchManager benchWithTitle:@"appDidBecomeReadyPoliteBlock" logIfLongerThan:0.01 logInProduction:YES block:block];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.025 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self runAppDidBecomeReadyPoliteBlocks:blocks];
    });
}

@end

NS_ASSUME_NONNULL_END
