//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AppReadiness.h"
#import <SignalCoreKit/Threading.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppReadiness ()

@property (atomic) BOOL isAppReady;

@property (nonatomic) NSMutableArray<AppReadyBlock> *appWillBecomeReadyBlocks;
@property (nonatomic) NSMutableArray<AppReadyBlock> *appDidBecomeReadyBlocks;

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

    // We invoke the _will become_ blocks before the _did become_ blocks.
    for (AppReadyBlock block in appWillBecomeReadyBlocks) {
        block();
    }
    for (AppReadyBlock block in appDidBecomeReadyBlocks) {
        block();
    }
}

@end

NS_ASSUME_NONNULL_END
