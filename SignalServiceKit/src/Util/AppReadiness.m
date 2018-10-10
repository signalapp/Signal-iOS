//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AppReadiness.h"
#import "SSKEnvironment.h"
#import <SignalCoreKit/Threading.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppReadiness ()

@property (atomic) BOOL isAppReady;

@property (nonatomic) NSMutableArray<AppReadyBlock> *appReadyBlocks;

@end

#pragma mark -

@implementation AppReadiness

+ (instancetype)sharedManager
{
    OWSAssertDebug(SSKEnvironment.shared.appReadiness);

    return SSKEnvironment.shared.appReadiness;
}

- (instancetype)initDefault
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    self.appReadyBlocks = [NSMutableArray new];

    return self;
}

+ (BOOL)isAppReady
{
    return [self.sharedManager isAppReady];
}

+ (void)runNowOrWhenAppIsReady:(AppReadyBlock)block
{
    DispatchMainThreadSafe(^{
        [self.sharedManager runNowOrWhenAppIsReady:block];
    });
}

- (void)runNowOrWhenAppIsReady:(AppReadyBlock)block
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(block);

    if (self.isAppReady) {
        block();
        return;
    }

    [self.appReadyBlocks addObject:block];
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

    NSArray<AppReadyBlock> *appReadyBlocks = [self.appReadyBlocks copy];
    [self.appReadyBlocks removeAllObjects];
    for (AppReadyBlock block in appReadyBlocks) {
        block();
    }
}

@end

NS_ASSUME_NONNULL_END
